# ADR-009: Deployment & Packaging

## Status
Accepted

## Context

Ingot must be deployable in multiple environments with varying infrastructure constraints:

1. **Local Development**: Single developer on laptop with Docker Compose (Postgres, MinIO, Ingot)
2. **Research Cluster**: Internal NSAI Kubernetes cluster with shared Postgres/S3, co-located Forge/Anvil apps
3. **Cloud Production**: AWS/GCP with managed services (RDS, S3), load-balanced Ingot web nodes
4. **Multi-Tenant SaaS** (future): Separate Ingot instances per customer, isolated data

**Deployment Requirements:**

- **Stateless Web Nodes**: Per ADR-001, Ingot has no persistent state (except optional auth DB). Horizontal scaling via load balancer.
- **Environment-Based Config**: Different Forge/Anvil endpoints per environment (localhost vs internal DNS vs public URL)
- **Asset Compilation**: Tailwind CSS, ESBuild for JS, Phoenix LiveView client bundling
- **Security**: CSP headers, secure session cookies, HTTPS enforcement, secret management
- **Health Checks**: Kubernetes readiness/liveness probes, load balancer health endpoints
- **Graceful Shutdown**: Drain LiveView connections before shutdown (avoid mid-labeling interruptions)
- **Hot Upgrades** (optional): Deploy new version without downtime via Erlang hot code swapping

**Current State (v0.1):**
- Development-only setup (mix phx.server)
- No release packaging
- Hardcoded config values
- No containerization

**Key Decisions:**

1. Release type: Mix release, Docker container, or OTP application?
2. Configuration strategy: compile-time vs runtime (ENV vars)?
3. Asset serving: Ingot serves vs CDN vs reverse proxy?
4. Load balancing: sticky sessions (for LiveView) or stateless?
5. Secrets management: ENV vars, Vault, AWS Secrets Manager?

## Decision

**Package Ingot as OTP release (mix release) with runtime configuration via ENV vars. Containerize with multi-stage Docker build. Deploy as stateless web nodes behind load balancer with sticky sessions. Assets compiled during build, served by Ingot (Phoenix.Static) or CDN. Secrets via ENV vars (local/k8s) or AWS Secrets Manager (cloud).**

### Architecture

```
┌────────────────────────────────────────────────┐
│         Load Balancer (sticky sessions)        │
│  - Routes based on session cookie              │
│  - Health checks /health endpoint              │
└────────────┬───────────────────────────────────┘
             │
     ┌───────┴────────┐
     │                │
     ▼                ▼
┌─────────┐      ┌─────────┐
│ Ingot-1 │      │ Ingot-2 │  ... (N nodes)
│ (Pod)   │      │ (Pod)   │
└────┬────┘      └────┬────┘
     │                │
     └────────┬───────┘
              │
              ▼
    ┌───────────────────┐
    │  Shared Services  │
    │  - Postgres (RDS) │
    │  - S3/MinIO       │
    │  - Forge App      │
    │  - Anvil App      │
    └───────────────────┘
```

### Release Configuration

**mix.exs:**

```elixir
defmodule Ingot.MixProject do
  use Mix.Project

  def project do
    [
      app: :ingot,
      version: "1.0.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Ingot.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp releases do
    [
      ingot: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
```

**Runtime Configuration (config/runtime.exs):**

```elixir
import Config

if config_env() == :prod do
  # Database
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :ingot, Ingot.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true

  # Phoenix Endpoint
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "ingot.nsai.io"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ingot, IngotWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true

  # Forge/Anvil Client Config
  config :ingot,
    forge_client_adapter: resolve_adapter(System.get_env("FORGE_ADAPTER", "elixir")),
    forge_base_url: System.get_env("FORGE_URL"),
    forge_timeout: String.to_integer(System.get_env("FORGE_TIMEOUT_MS") || "5000"),
    anvil_client_adapter: resolve_adapter(System.get_env("ANVIL_ADAPTER", "elixir")),
    anvil_base_url: System.get_env("ANVIL_URL"),
    anvil_timeout: String.to_integer(System.get_env("ANVIL_TIMEOUT_MS") || "5000")

  # OIDC Config
  if System.get_env("OIDC_CLIENT_ID") do
    config :ingot, :oidc,
      provider: System.fetch_env!("OIDC_PROVIDER"),
      client_id: System.fetch_env!("OIDC_CLIENT_ID"),
      client_secret: System.fetch_env!("OIDC_CLIENT_SECRET"),
      redirect_uri: System.get_env("OIDC_REDIRECT_URI", "https://#{host}/auth/callback")
  end

  # S3 Config (for artifact URLs)
  config :ex_aws,
    access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
    region: System.get_env("AWS_REGION", "us-east-1")

  # Telemetry
  config :ingot, :telemetry,
    prometheus_enabled: System.get_env("PROMETHEUS_ENABLED", "true") == "true",
    log_level: String.to_atom(System.get_env("LOG_LEVEL", "info"))
end

defp resolve_adapter("elixir"), do: Ingot.ForgeClient.ElixirAdapter
defp resolve_adapter("http"), do: Ingot.ForgeClient.HTTPAdapter
```

### Dockerfile (Multi-Stage Build)

```dockerfile
# Build stage
FROM hexpm/elixir:1.17.3-erlang-27.1.2-alpine-3.20.3 AS build

# Install build dependencies
RUN apk add --no-cache build-base git npm

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Copy dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy assets
COPY assets assets
COPY priv priv

# Compile assets
RUN cd assets && npm install && npm run deploy
RUN mix phx.digest

# Copy application code
COPY lib lib
COPY config config

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.20.3 AS app

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

# Create non-root user
RUN adduser -D ingot
USER ingot

# Copy release from build stage
COPY --from=build --chown=ingot:ingot /app/_build/prod/rel/ingot ./

ENV HOME=/app

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/app/bin/ingot", "rpc", "Ingot.HealthCheck.status()"]

# Start release
CMD ["/app/bin/ingot", "start"]
```

### Kubernetes Deployment

**deployment.yaml:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ingot
  namespace: research
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ingot
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: ingot
        version: "1.0.0"
    spec:
      containers:
      - name: ingot
        image: gcr.io/nsai/ingot:1.0.0
        ports:
        - containerPort: 4000
          name: http
        env:
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: ingot-secrets
              key: secret-key-base
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: ingot-secrets
              key: database-url
        - name: FORGE_URL
          value: "http://forge.research.svc.cluster.local:4001"
        - name: ANVIL_URL
          value: "http://anvil.research.svc.cluster.local:4002"
        - name: FORGE_ADAPTER
          value: "elixir"
        - name: ANVIL_ADAPTER
          value: "elixir"
        - name: PHX_HOST
          value: "ingot.nsai.io"
        - name: POOL_SIZE
          value: "10"
        - name: LOG_LEVEL
          value: "info"
        - name: PROMETHEUS_ENABLED
          value: "true"
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: aws-credentials
              key: access-key-id
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: aws-credentials
              key: secret-access-key
        - name: AWS_REGION
          value: "us-east-1"
        - name: OIDC_PROVIDER
          value: "https://auth.nsai.io"
        - name: OIDC_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: oidc-secrets
              key: client-id
        - name: OIDC_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: oidc-secrets
              key: client-secret

        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"

        livenessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 10

        readinessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 10
          periodSeconds: 5

        lifecycle:
          preStop:
            exec:
              command: ["/app/bin/ingot", "rpc", "Ingot.GracefulShutdown.drain()"]

---
apiVersion: v1
kind: Service
metadata:
  name: ingot
  namespace: research
spec:
  type: LoadBalancer
  sessionAffinity: ClientIP  # Sticky sessions for LiveView
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800  # 3 hours
  selector:
    app: ingot
  ports:
  - port: 80
    targetPort: 4000
    protocol: TCP
    name: http

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingot
  namespace: research
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "ingot_affinity"
    nginx.ingress.kubernetes.io/session-cookie-hash: "sha1"
spec:
  tls:
  - hosts:
    - ingot.nsai.io
    secretName: ingot-tls
  rules:
  - host: ingot.nsai.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ingot
            port:
              number: 80
```

### Secrets Management

**Kubernetes Secrets:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ingot-secrets
  namespace: research
type: Opaque
stringData:
  secret-key-base: "<generated-with-mix-phx.gen.secret>"
  database-url: "ecto://user:pass@postgres.research.svc.cluster.local/nsai_research"
```

**AWS Secrets Manager (for cloud deployments):**

```elixir
# config/runtime.exs
if System.get_env("USE_AWS_SECRETS") == "true" do
  {:ok, secret} = ExAws.SecretsManager.get_secret_value("ingot/prod")
    |> ExAws.request()

  secrets = Jason.decode!(secret["SecretString"])

  config :ingot, IngotWeb.Endpoint,
    secret_key_base: secrets["secret_key_base"]

  config :ingot, Ingot.Repo,
    url: secrets["database_url"]
end
```

### Asset Compilation

**assets/package.json:**

```json
{
  "scripts": {
    "deploy": "NODE_ENV=production tailwindcss --postcss --minify -i css/app.css -o ../priv/static/assets/app.css && esbuild js/app.js --bundle --minify --outdir=../priv/static/assets --external:/fonts/* --external:/images/*"
  },
  "dependencies": {
    "phoenix": "file:../deps/phoenix",
    "phoenix_html": "file:../deps/phoenix_html",
    "phoenix_live_view": "file:../deps/phoenix_live_view"
  },
  "devDependencies": {
    "@tailwindcss/forms": "^0.5.2",
    "autoprefixer": "^10.4.7",
    "esbuild": "^0.14.41",
    "postcss": "^8.4.14",
    "tailwindcss": "^3.1.0"
  }
}
```

**CDN Deployment (Optional):**

For high-traffic deployments, serve static assets from CDN:

```elixir
# config/prod.exs
config :ingot, IngotWeb.Endpoint,
  static_url: [host: "cdn.nsai.io", port: 443, scheme: "https"]

# Upload assets to S3/CloudFront during build
# aws s3 sync priv/static s3://nsai-assets/ingot/1.0.0/
```

### Graceful Shutdown

```elixir
defmodule Ingot.GracefulShutdown do
  @moduledoc """
  Drains LiveView connections before shutdown.
  Called by Kubernetes preStop hook.
  """

  def drain do
    # Stop accepting new connections
    Phoenix.Endpoint.broadcast(IngotWeb.Endpoint, "shutdown", %{})

    # Wait for active LiveView sessions to complete (max 30s)
    wait_for_drain(30)

    :ok
  end

  defp wait_for_drain(0), do: :ok
  defp wait_for_drain(seconds_left) do
    active_sessions = count_active_sessions()

    if active_sessions == 0 do
      :ok
    else
      :timer.sleep(1000)
      wait_for_drain(seconds_left - 1)
    end
  end

  defp count_active_sessions do
    # Count active LiveView processes
    Phoenix.LiveView.Socket
    |> Process.whereis()
    |> case do
      nil -> 0
      pid -> :sys.get_state(pid) |> Map.get(:channels, %{}) |> map_size()
    end
  end
end
```

### Health Check Implementation

```elixir
defmodule Ingot.HealthCheck do
  @moduledoc """
  Health check for load balancer and Kubernetes probes.
  """

  def status do
    checks = [
      check_endpoint(),
      check_forge(),
      check_anvil(),
      check_database()
    ]

    if Enum.all?(checks, & &1 == :ok) do
      :healthy
    else
      :unhealthy
    end
  end

  defp check_endpoint do
    if Process.whereis(IngotWeb.Endpoint), do: :ok, else: :error
  end

  defp check_forge do
    case Ingot.ForgeClient.health_check() do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp check_anvil do
    case Ingot.AnvilClient.health_check() do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Ingot.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
```

### CSP Headers (Security)

```elixir
# lib/ingot_web/endpoint.ex
defmodule IngotWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ingot

  plug Plug.Static,
    at: "/",
    from: :ingot,
    gzip: true,
    only: IngotWeb.static_paths()

  # Security headers
  plug :put_security_headers

  defp put_security_headers(conn, _opts) do
    conn
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("content-security-policy", csp_policy())
    |> put_resp_header("strict-transport-security", "max-age=31536000; includeSubDomains")
  end

  defp csp_policy do
    """
    default-src 'self';
    script-src 'self' 'unsafe-inline' 'unsafe-eval';
    style-src 'self' 'unsafe-inline';
    img-src 'self' data: https://s3.amazonaws.com https://cdn.nsai.io;
    font-src 'self';
    connect-src 'self' wss://ingot.nsai.io;
    frame-ancestors 'none';
    """
    |> String.replace("\n", " ")
  end
end
```

### CI/CD Pipeline (GitHub Actions)

```yaml
# .github/workflows/deploy.yml
name: Build and Deploy

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.17.3'
        otp-version: '27.1'

    - name: Restore dependencies cache
      uses: actions/cache@v3
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

    - name: Install dependencies
      run: mix deps.get

    - name: Run tests
      run: mix test

    - name: Build Docker image
      run: |
        docker build -t gcr.io/nsai/ingot:${{ github.sha }} .
        docker tag gcr.io/nsai/ingot:${{ github.sha }} gcr.io/nsai/ingot:latest

    - name: Push to GCR
      run: |
        echo ${{ secrets.GCP_SA_KEY }} | docker login -u _json_key --password-stdin https://gcr.io
        docker push gcr.io/nsai/ingot:${{ github.sha }}
        docker push gcr.io/nsai/ingot:latest

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/ingot ingot=gcr.io/nsai/ingot:${{ github.sha }} -n research
        kubectl rollout status deployment/ingot -n research
```

## Consequences

### Positive

- **Portable Deployment**: Docker container runs anywhere (local Docker, K8s, ECS, Cloud Run). Same artifact across environments.

- **Horizontal Scaling**: Stateless nodes scale out easily. Add more pods to K8s deployment, load balancer distributes traffic.

- **Environment Flexibility**: Runtime config via ENV vars allows same release artifact to run in dev/staging/prod with different settings.

- **Security**: CSP headers, HTTPS enforcement, secure session cookies, secrets in K8s secrets/AWS SM (not in code).

- **Zero-Downtime Deploys**: Rolling update with preStop hook drains connections. MaxUnavailable=0 ensures no dropped requests.

- **Observability Integration**: Health checks for load balancer, readiness probes for K8s, Prometheus metrics endpoint.

### Negative

- **Release Artifact Size**: Docker image ~100MB (includes BEAM, Erlang libs, assets). Larger than static binaries.
  - *Mitigation*: Use Alpine base image (smaller), multi-stage build (excludes build tools from runtime image).

- **Sticky Session Requirement**: LiveView WebSockets require session affinity. Complicates load balancer config.
  - *Mitigation*: Use cookie-based affinity (ClientIP or session cookie hash). Nginx/K8s ingress support this.

- **Secret Rotation**: Changing secrets (database password) requires pod restart.
  - *Mitigation*: Use K8s secret reloader (watches secrets, restarts pods on change). Or use Vault dynamic secrets.

- **Build Time**: Multi-stage Docker build takes 5-10 minutes (deps download, asset compilation).
  - *Mitigation*: Cache deps in CI (GitHub Actions cache). Only rebuild on mix.lock changes.

### Neutral

- **Hot Upgrades**: OTP releases support hot code swapping, but Docker deployments typically use rolling updates instead.
  - Trade-off: Hot upgrades are complex (test extensively). Rolling updates are simpler, well-tested.

- **Asset Serving**: Phoenix serves static assets efficiently, but CDN offloads traffic for high-scale.
  - Use Phoenix.Static for simplicity, migrate to CDN if traffic grows (>10K users).

## Implementation Checklist

1. Configure `config/runtime.exs` for ENV-based settings
2. Create multi-stage Dockerfile
3. Add `mix release` configuration
4. Implement `Ingot.HealthCheck` module
5. Implement `Ingot.GracefulShutdown` for preStop hook
6. Add security headers to Phoenix.Endpoint
7. Create Kubernetes manifests (deployment, service, ingress)
8. Set up K8s secrets for sensitive ENV vars
9. Configure CI/CD pipeline (GitHub Actions)
10. Write deployment runbook (how to deploy, rollback)
11. Test horizontal scaling (3+ pods, load test)
12. Document ENV vars in README

## Deployment Runbook (Summary)

**Deploy New Version:**
```bash
# Tag release
git tag v1.1.0
git push origin v1.1.0

# CI builds and pushes Docker image
# Manual deploy:
kubectl set image deployment/ingot ingot=gcr.io/nsai/ingot:v1.1.0 -n research
kubectl rollout status deployment/ingot -n research
```

**Rollback:**
```bash
kubectl rollout undo deployment/ingot -n research
```

**Scale:**
```bash
kubectl scale deployment/ingot --replicas=5 -n research
```

**View Logs:**
```bash
kubectl logs -f deployment/ingot -n research
```

**Check Health:**
```bash
curl https://ingot.nsai.io/health
```

## Related ADRs

- ADR-001: Stateless UI Architecture (enables horizontal scaling)
- ADR-004: Persistence Strategy (DATABASE_URL config)
- ADR-008: Telemetry & Observability (health checks, Prometheus)
