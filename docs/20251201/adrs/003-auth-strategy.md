# ADR-003: Auth Strategy

## Status
Accepted

## Context

Ingot serves multiple user personas with different access requirements:

1. **Labelers**: Human annotators who complete assignments from queues. May be internal researchers or external contractors.
2. **Admins**: Operators who configure queues, monitor progress, review labels, and trigger exports.
3. **Auditors**: Read-only access to label history, agreement metrics, and audit logs for quality control.
4. **Adjudicators**: Specialized role for resolving disagreements between labelers.

**Authentication Requirements:**
- Support both internal users (NSAI researchers with SSO) and external labelers (contractors without org accounts)
- Integration with existing NSAI identity infrastructure where possible
- Secure session management for web-based labeling
- API access for programmatic queue management

**Authorization Requirements:**
- Role-based access control (RBAC) for different user types
- Queue-level permissions (some labelers only access specific queues)
- Audit trail of who labeled what and when
- External labelers should not see organizational data beyond their assignments

**Deployment Contexts:**
- Single-tenant research deployments (trust internal network)
- Multi-tenant SaaS (strong isolation required)
- Hybrid scenarios (internal admins + external labelers)

**Current State (v0.1):**
- No authentication system
- No authorization checks
- Session management via Phoenix defaults (ETS-based, unencrypted)

**Key Decisions:**
1. Primary authentication mechanism (OIDC, local accounts, hybrid)?
2. Where are roles/permissions stored and enforced (Ingot, Anvil, IdP)?
3. How to onboard external labelers without org accounts?
4. Session storage (stateful vs stateless tokens)?

## Decision

**Use OIDC (OpenID Connect) as primary authentication mechanism for internal users, with hybrid invite-code flow for external labelers. Store role definitions and queue permissions in Anvil (authoritative), with Ingot reading via AnvilClient. Sessions managed via signed Phoenix tokens with minimal server-side state.**

### Architecture

```
┌──────────────────────────────────────────────────────┐
│                    OIDC Provider                     │
│        (Keycloak, Auth0, Google Workspace)           │
└────────────────┬─────────────────────────────────────┘
                 │
                 │ (1) Login redirect
                 │ (2) Authorization code
                 │ (3) Token exchange
                 ▼
┌──────────────────────────────────────────────────────┐
│                  Ingot Web Layer                     │
│  ┌────────────────────────────────────────────────┐  │
│  │         Authentication Plug Pipeline          │  │
│  │  - OIDC callback handler                      │  │
│  │  - Invite code validator (external labelers)  │  │
│  │  - Session token verifier                     │  │
│  └────────────┬───────────────────────────────────┘  │
│               │                                      │
│               ▼                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │        Authorization Layer (via Anvil)        │  │
│  │  AnvilClient.get_user_roles(user_id)          │  │
│  │  AnvilClient.check_queue_access(user, queue)  │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────┐
│                 Anvil (Authorization)                │
│  ┌────────────────────────────────────────────────┐  │
│  │  users (id, external_id, email, created_at)   │  │
│  │  user_roles (user_id, role, scope)            │  │
│  │  queue_access (queue_id, user_id, granted_by) │  │
│  │  invite_codes (code, queue_id, role, uses)    │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### Authentication Flows

#### Flow 1: Internal User (OIDC)

```
Researcher → Ingot → OIDC Provider
1. User visits https://ingot.nsai.io
2. Not authenticated → redirect to OIDC login
3. User logs in with SSO (Google/NSAI Keycloak)
4. OIDC returns authorization code to /auth/oidc/callback
5. Ingot exchanges code for ID token + access token
6. Extract user claims (sub, email, name)
7. Upsert user in Anvil: AnvilClient.upsert_user(%{external_id: sub, email: email})
8. Fetch roles: AnvilClient.get_user_roles(user_id)
9. Generate signed session token, set cookie
10. Redirect to /dashboard or /queue/:id
```

Implementation:
```elixir
defmodule IngotWeb.AuthController do
  use IngotWeb, :controller
  alias Ingot.AnvilClient

  def login(conn, _params) do
    # Redirect to OIDC provider
    redirect_uri = Routes.auth_url(conn, :callback)
    oidc_url = build_oidc_url(redirect_uri)
    redirect(conn, external: oidc_url)
  end

  def callback(conn, %{"code" => code}) do
    # Exchange authorization code for tokens
    {:ok, tokens} = exchange_code(code)
    {:ok, claims} = verify_id_token(tokens["id_token"])

    # Upsert user in Anvil
    {:ok, user} = AnvilClient.upsert_user(%{
      external_id: claims["sub"],
      email: claims["email"],
      name: claims["name"]
    })

    # Fetch roles from Anvil
    {:ok, roles} = AnvilClient.get_user_roles(user.id)

    # Create session
    conn
    |> put_session(:user_id, user.id)
    |> put_session(:user_email, user.email)
    |> put_session(:roles, Enum.map(roles, & &1.role))
    |> configure_session(renew: true)
    |> redirect(to: ~p"/dashboard")
  end
end
```

#### Flow 2: External Labeler (Invite Code)

```
External Labeler → Ingot (Invite Code)
1. Admin generates invite code in Anvil: AnvilClient.create_invite("queue_123", role: :labeler, max_uses: 10)
2. Admin shares URL: https://ingot.nsai.io/invite/ABC123XYZ
3. Labeler visits URL, sees invite landing page
4. Labeler provides email/name (optional identity)
5. Ingot validates code with Anvil: AnvilClient.redeem_invite("ABC123XYZ", email: "labeler@example.com")
6. Anvil creates user + queue_access grant
7. Ingot generates session token for anonymous labeler
8. Redirect to /queue/:id (only accessible queue)
```

Implementation:
```elixir
defmodule IngotWeb.InviteLive do
  use IngotWeb, :live_view
  alias Ingot.AnvilClient

  def mount(%{"code" => invite_code}, _session, socket) do
    case AnvilClient.get_invite(invite_code) do
      {:ok, invite} ->
        {:ok, assign(socket, invite: invite, email: "", name: "")}

      {:error, :not_found} ->
        {:ok, redirect(socket, to: ~p"/error/invalid_invite")}
    end
  end

  def handle_event("redeem", %{"email" => email, "name" => name}, socket) do
    %{invite: invite} = socket.assigns

    case AnvilClient.redeem_invite(invite.code, email: email, name: name) do
      {:ok, user} ->
        # Create limited session (only access to invited queue)
        socket =
          socket
          |> put_session(:user_id, user.id)
          |> put_session(:user_email, email)
          |> put_session(:roles, ["labeler"])
          |> put_session(:invite_queue_id, invite.queue_id)

        {:noreply, redirect(socket, to: ~p"/queue/#{invite.queue_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to redeem invite: #{reason}")}
    end
  end
end
```

### Role Model

Roles are stored in Anvil with hierarchical semantics:

```elixir
# Anvil schema
defmodule Anvil.UserRole do
  schema "user_roles" do
    field :user_id, :string
    field :role, Ecto.Enum, values: [:admin, :labeler, :auditor, :adjudicator]
    field :scope, :string  # "global" or "queue:queue_id"
    timestamps()
  end
end

# Examples:
%UserRole{user_id: "user_1", role: :admin, scope: "global"}
%UserRole{user_id: "user_2", role: :labeler, scope: "queue:queue_123"}
%UserRole{user_id: "user_3", role: :auditor, scope: "global"}
```

**Role Permissions:**

| Role | Can Label | View Queues | Admin Controls | Adjudicate | Export Data |
|------|-----------|-------------|----------------|------------|-------------|
| `admin` | Yes | All | Yes | Yes | Yes |
| `labeler` | Yes | Assigned only | No | No | No |
| `auditor` | No | All (read-only) | No | No | Yes |
| `adjudicator` | Yes | Flagged samples | No | Yes | No |

**Enforcement in Ingot:**

```elixir
defmodule IngotWeb.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller
  alias Ingot.AnvilClient

  def require_role(conn, opts) do
    required_role = Keyword.fetch!(opts, :role)
    user_id = get_session(conn, :user_id)

    case AnvilClient.get_user_roles(user_id) do
      {:ok, roles} ->
        if has_role?(roles, required_role) do
          conn
        else
          conn
          |> put_flash(:error, "Insufficient permissions")
          |> redirect(to: ~p"/")
          |> halt()
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "Authorization failed")
        |> redirect(to: ~p"/login")
        |> halt()
    end
  end

  def require_queue_access(conn, queue_id) do
    user_id = get_session(conn, :user_id)

    case AnvilClient.check_queue_access(user_id, queue_id) do
      {:ok, true} ->
        conn

      {:ok, false} ->
        conn
        |> put_flash(:error, "No access to this queue")
        |> redirect(to: ~p"/")
        |> halt()

      {:error, _} ->
        conn
        |> put_flash(:error, "Authorization check failed")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  defp has_role?(roles, required_role) do
    Enum.any?(roles, fn role ->
      role.role == required_role or (role.role == :admin and role.scope == "global")
    end)
  end
end

# Usage in router
pipeline :labeler_required do
  plug IngotWeb.AuthPlug, :require_role, role: :labeler
end

live "/queue/:id", QueueLive, :show do
  pipe_through [:browser, :labeler_required]
  on_mount {IngotWeb.AuthPlug, :require_queue_access}
end
```

### Session Management

**Token-Based Sessions (Stateless):**

```elixir
# config/config.exs
config :ingot, IngotWeb.Endpoint,
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  live_view: [signing_salt: System.get_env("LIVE_VIEW_SALT")]

# Session stored in encrypted cookie (Phoenix default)
# Contains: user_id, roles, email, expires_at
# Max size: 4KB (sufficient for user data)

defmodule IngotWeb.SessionManager do
  @session_ttl_hours 24

  def create_session(conn, user) do
    conn
    |> put_session(:user_id, user.id)
    |> put_session(:user_email, user.email)
    |> put_session(:roles, user.roles)
    |> put_session(:expires_at, expires_at())
    |> configure_session(renew: true)
  end

  defp expires_at do
    DateTime.utc_now()
    |> DateTime.add(@session_ttl_hours, :hour)
    |> DateTime.to_unix()
  end
end

# Session validation plug
defmodule IngotWeb.ValidateSession do
  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :expires_at) do
      nil ->
        redirect_to_login(conn)

      expires_at when expires_at < DateTime.utc_now() |> DateTime.to_unix() ->
        conn
        |> clear_session()
        |> redirect_to_login()

      _ ->
        conn
    end
  end

  defp redirect_to_login(conn) do
    conn
    |> Phoenix.Controller.redirect(to: "/login")
    |> halt()
  end
end
```

**Optional: Server-Side Session Store (For High-Security)**

For deployments requiring session revocation:

```elixir
# Anvil schema
CREATE TABLE user_sessions (
  token TEXT PRIMARY KEY,
  user_id UUID NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  revoked_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

# Ingot validates session with Anvil
def validate_session(conn) do
  token = get_session(conn, :session_token)

  case AnvilClient.validate_session(token) do
    {:ok, session} ->
      assign(conn, :current_user, session.user)

    {:error, :expired} ->
      redirect_to_login(conn)

    {:error, :revoked} ->
      redirect_to_login(conn)
  end
end
```

### OIDC Configuration

```elixir
# config/runtime.exs
config :ingot, :oidc,
  provider: System.get_env("OIDC_PROVIDER", "https://auth.nsai.io"),
  client_id: System.fetch_env!("OIDC_CLIENT_ID"),
  client_secret: System.fetch_env!("OIDC_CLIENT_SECRET"),
  redirect_uri: System.get_env("OIDC_REDIRECT_URI", "https://ingot.nsai.io/auth/callback"),
  scopes: ["openid", "email", "profile"]

# OIDC discovery
defmodule Ingot.OIDC do
  def discovery_url do
    provider = Application.fetch_env!(:ingot, :oidc)[:provider]
    "#{provider}/.well-known/openid-configuration"
  end

  def authorization_url(state) do
    config = Application.fetch_env!(:ingot, :oidc)
    discovery = fetch_discovery()

    params = %{
      client_id: config[:client_id],
      redirect_uri: config[:redirect_uri],
      response_type: "code",
      scope: Enum.join(config[:scopes], " "),
      state: state
    }

    "#{discovery["authorization_endpoint"]}?#{URI.encode_query(params)}"
  end

  def exchange_code(code) do
    config = Application.fetch_env!(:ingot, :oidc)
    discovery = fetch_discovery()

    HTTPoison.post(
      discovery["token_endpoint"],
      {:form, [
        grant_type: "authorization_code",
        code: code,
        redirect_uri: config[:redirect_uri],
        client_id: config[:client_id],
        client_secret: config[:client_secret]
      ]}
    )
  end
end
```

## Consequences

### Positive

- **Standards-Based**: OIDC integrates with existing identity providers (Keycloak, Auth0, Google Workspace) without custom auth code.

- **Flexible Onboarding**: Internal users use SSO, external labelers use invite codes. No need to provision org accounts for contractors.

- **Centralized Authorization**: Roles stored in Anvil (authoritative for labeling permissions). Ingot reads via client, no duplicate role tables.

- **Audit Trail**: Anvil tracks user creation, role grants, invite redemptions. All label submissions linked to user_id for compliance.

- **Scalable Sessions**: Token-based sessions (signed cookies) require no server-side storage. Scales horizontally without shared session store.

- **Revocation Support**: Optional server-side session table in Anvil enables admin-initiated logout (revoke session token).

### Negative

- **OIDC Dependency**: Requires external IdP for internal users. Adds network hop during login.
  - *Mitigation*: Cache OIDC discovery metadata. Session tokens last 24h, reducing login frequency.
  - *Mitigation*: Graceful degradation: if OIDC unavailable, show maintenance page (labeling requires auth).

- **Invite Code Abuse**: External labelers could share invite URLs.
  - *Mitigation*: Invite codes have max_uses limit and expiration. Admins monitor redemption logs.
  - *Mitigation*: Email-based tracking (Anvil stores email from invite redemption). Rate-limit label submissions.

- **Session Invalidation Complexity**: Cookie-based sessions can't be immediately revoked without server-side store.
  - *Mitigation*: Short session TTL (24h). For high-security deployments, enable server-side session store.

- **Multi-Provider Complexity**: Supporting multiple OIDC providers (Google, GitHub, NSAI Keycloak) requires provider selection UI.
  - *Mitigation*: Start with single provider. Add multi-provider in v2 if needed.

### Neutral

- **Role Caching**: Ingot reads roles from Anvil on each request. Could cache in session, but adds staleness risk.
  - Trade-off: Fetch roles on session creation, store in cookie. Re-fetch periodically or on explicit permission changes.

- **API Authentication**: For programmatic access (e.g., admin scripts), support API keys stored in Anvil.
  ```elixir
  # Anvil schema
  CREATE TABLE api_keys (
    key TEXT PRIMARY KEY,
    user_id UUID NOT NULL,
    description TEXT,
    last_used TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
  );

  # Header: Authorization: Bearer <api_key>
  ```

## Implementation Checklist

1. Configure OIDC provider (Keycloak/Auth0)
2. Implement `IngotWeb.AuthController` (login, callback, logout)
3. Add `IngotWeb.AuthPlug` for role checks
4. Extend AnvilClient with:
   - `upsert_user/1`
   - `get_user_roles/1`
   - `check_queue_access/2`
   - `create_invite/2`
   - `redeem_invite/2`
5. Implement `IngotWeb.InviteLive` for external labeler onboarding
6. Add session validation plug to router pipeline
7. Write tests for auth flows (OIDC, invite code, role enforcement)
8. Document deployment: ENV vars for OIDC config
9. (Optional) Implement server-side session store for revocation

## Security Considerations

- **CSRF Protection**: Phoenix default CSRF tokens protect form submissions.
- **XSS Prevention**: LiveView escapes all user input. Admin-controlled content (queue configs) still escaped.
- **Session Fixation**: `configure_session(renew: true)` regenerates session ID after login.
- **Secret Management**: OIDC client secret and Phoenix secret_key_base in ENV vars, never committed.
- **HTTPS Required**: Session cookies marked `secure: true` in production, enforce HTTPS redirects.
- **Rate Limiting**: Add `Plug.Attack` or `Hammer` for login endpoint (prevent brute-force).

## Related ADRs

- ADR-001: Stateless UI Architecture (minimal auth state)
- ADR-002: Client Layer Design (AnvilClient for role fetching)
- ADR-004: Persistence Strategy (roles stored in Anvil, not Ingot)
