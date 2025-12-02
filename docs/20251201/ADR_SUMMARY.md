# Ingot Architecture Decision Records - Summary

**Date**: 2025-12-01
**Purpose**: Complete set of ADRs for Ingot repository based on buildout plan
**Total ADRs**: 10 (plus README index)
**Total Lines**: ~6,000 lines of technical documentation

## Files Created

All files located in: `/home/home/p/g/North-Shore-AI/ingot/docs/20251201/adrs/`

1. **README.md** (113 lines)
   - ADR index with status table
   - Reading guide for different roles
   - Architectural principles summary

2. **001-stateless-ui-architecture.md** (223 lines)
   - Core principle: Ingot owns no domain data
   - Delegates to Forge (samples) and Anvil (labels)
   - Session-scoped state only

3. **002-client-layer-design.md** (534 lines)
   - ForgeClient and AnvilClient behaviors
   - DTO translation layer
   - Retry strategies, circuit breakers, timeouts
   - Elixir adapter (in-cluster) + HTTP adapter (remote)

4. **003-auth-strategy.md** (521 lines)
   - OIDC for internal users
   - Invite codes for external labelers
   - Role model: admin, labeler, auditor, adjudicator
   - Roles stored in Anvil (authoritative)

5. **004-persistence-strategy.md** (564 lines)
   - Single Postgres cluster with separate schemas
   - Forge schema, Anvil schema, optional Ingot auth schema
   - Blob storage via MinIO/S3 with signed URLs
   - No per-repo database instances

6. **005-realtime-ux.md** (669 lines)
   - LiveView + PubSub for real-time updates
   - Progress indicators, keyboard shortcuts
   - Telemetry integration for live metrics
   - Mobile-responsive layouts, accessibility

7. **006-admin-dashboard.md** (816 lines)
   - Queue controls (pause/resume, policy updates)
   - Agreement visualization (charts, leaderboards)
   - Label review and adjudication workflows
   - Export management, audit log viewer

8. **007-pluggable-components.md** (744 lines)
   - Runtime component registration via behaviors
   - SampleRenderer and LabelFormRenderer contracts
   - CNS.IngotComponents as reference implementation
   - DefaultComponent fallback for generic samples

9. **008-telemetry-observability.md** (663 lines)
   - Subscribe to Forge/Anvil telemetry events
   - Prometheus metrics export
   - Distributed tracing (Foundation/AITrace)
   - Structured JSON logging for ELK/Loki

10. **009-deployment-packaging.md** (764 lines)
    - OTP release with Docker multi-stage build
    - Kubernetes deployment manifests
    - ENV-based runtime configuration
    - Health checks, graceful shutdown, CSP headers

11. **010-offline-and-pwa.md** (450 lines)
    - Decision: Online-only with optimistic UI
    - Rationale: CNS use case has reliable connectivity
    - Future offline architecture documented
    - Decision criteria for PWA implementation

## Key Architectural Decisions

### 1. Stateless Design (ADR-001, 004)
- Ingot does NOT store samples, labels, or domain data
- All persistence in Forge/Anvil
- Enables horizontal scaling, simplifies deployment

### 2. Client Abstraction (ADR-002)
- Behavior-based client modules (ForgeClient, AnvilClient)
- DTO layer decouples UI from internal structs
- Swappable adapters (Elixir vs HTTP)
- Resilience patterns: retries, circuit breakers, timeouts

### 3. Hybrid Auth (ADR-003)
- OIDC for internal researchers (SSO integration)
- Invite codes for external contractors (no org accounts needed)
- Roles enforced by Anvil (authoritative), Ingot reads via client

### 4. Shared Infrastructure (ADR-004)
- Single Postgres cluster with schemas (forge, anvil, ingot)
- Shared MinIO/S3 for blobs
- Reduces operational complexity vs per-repo instances

### 5. Real-Time UX (ADR-005)
- LiveView provides WebSocket-based updates
- PubSub broadcasts telemetry from Forge/Anvil
- Keyboard shortcuts for power users
- Optimistic UI (instant feedback, async submission)

### 6. Admin Tooling (ADR-006)
- Comprehensive dashboard for queue management
- Agreement visualization, labeler leaderboards
- Adjudication workflow for disagreements
- One-click exports (JSONL, CSV, Parquet)

### 7. Extensibility (ADR-007)
- Pluggable components via runtime registration
- CNS provides custom narrative rendering
- Components declare CSS/JS dependencies
- DefaultComponent for generic samples

### 8. Observability (ADR-008)
- Telemetry handlers convert events → PubSub + metrics
- Prometheus metrics for alerting
- Distributed tracing via Foundation/AITrace
- Health checks for load balancers

### 9. Cloud-Native Deployment (ADR-009)
- Docker containers, Kubernetes manifests
- Stateless web nodes with sticky sessions
- ENV-based config (12-factor app)
- Graceful shutdown, zero-downtime deploys

### 10. Pragmatic Offline Strategy (ADR-010)
- Online-only for CNS (reliable connectivity)
- Optimistic UI reduces perceived latency
- Offline PWA reserved for future use cases
- Decision criteria documented for re-evaluation

## Technical Highlights

### Elixir/Phoenix Stack
- Phoenix LiveView for real-time UI
- OTP release packaging
- Ecto for database access (minimal, read-only via clients)
- PubSub for event broadcasting

### Infrastructure
- Kubernetes deployment (3+ replicas)
- Postgres 14+ (single cluster, multiple schemas)
- MinIO/S3 for blob storage
- Prometheus + ELK/Loki for observability

### Security
- OIDC (OpenID Connect) authentication
- RBAC (role-based access control)
- CSP (Content Security Policy) headers
- HTTPS enforcement, secure session cookies

### Integrations
- Forge: Sample factory (pipelines, artifacts)
- Anvil: Labeling queue (assignments, labels, agreement)
- Foundation/AITrace: Distributed tracing
- CNS: First domain-specific component

## Implementation Guidance

### For Engineers Building Ingot

**Phase 1: Core Infrastructure**
1. Implement client layer (ADR-002): ForgeClient, AnvilClient
2. Set up auth (ADR-003): OIDC integration, invite codes
3. Configure persistence (ADR-004): Postgres schemas, S3 access

**Phase 2: User Interfaces**
4. Build labeling UI (ADR-005): LiveView, PubSub, keyboard shortcuts
5. Build admin dashboard (ADR-006): Queue controls, label review
6. Add telemetry (ADR-008): Prometheus metrics, health checks

**Phase 3: Extensibility & Ops**
7. Implement component system (ADR-007): Behavior contracts, CNS integration
8. Package for deployment (ADR-009): Dockerfile, K8s manifests
9. Add optimistic UI (ADR-010): Pre-fetching, background submission

### For Domain Teams (e.g., CNS)

To integrate domain-specific UI:

1. Implement `Ingot.SampleRenderer` and `Ingot.LabelFormRenderer` behaviors
2. Create component module (e.g., `CNS.IngotComponents`)
3. Bundle CSS/JS assets in `priv/static/`
4. Register in Anvil queue metadata: `component_module: "CNS.IngotComponents"`
5. Test with Ingot in dev environment

See ADR-007 for complete component developer guide.

## Design Trade-Offs

### Stateless vs Stateful
**Decision**: Stateless (ADR-001)
**Trade-off**: Higher latency (network calls) vs simpler scaling
**Rationale**: CNS workflow tolerates 100-500ms latency, horizontal scaling more important

### Client Calls: Direct vs HTTP
**Decision**: Swappable adapters (ADR-002)
**Trade-off**: In-cluster (fast) vs remote (flexible deployment)
**Rationale**: Elixir adapter for co-located, HTTP adapter for separate deployments

### Auth: Local vs External
**Decision**: Hybrid (ADR-003)
**Trade-off**: OIDC complexity vs invite code simplicity
**Rationale**: Internal users need SSO, external labelers need frictionless onboarding

### Persistence: Per-Repo vs Shared
**Decision**: Shared Postgres cluster (ADR-004)
**Trade-off**: Coupling risk vs operational simplicity
**Rationale**: Single-tenant research deployment, lineage queries require joins

### Offline: Full PWA vs Online-Only
**Decision**: Online-only with optimistic UI (ADR-010)
**Trade-off**: Offline capability vs implementation complexity
**Rationale**: CNS labelers have reliable connectivity, conflict resolution not worth cost

## Success Metrics

ADRs define these success criteria:

1. **Performance**: p95 label submission latency <500ms (ADR-005, 008)
2. **Scalability**: 100+ concurrent labelers per node (ADR-001, 009)
3. **Availability**: 99.9% uptime via health checks, graceful shutdown (ADR-009)
4. **Quality**: Inter-labeler agreement >80% tracked via dashboard (ADR-006)
5. **Security**: Zero auth bypass vulnerabilities, OIDC compliance (ADR-003)
6. **Extensibility**: New domain component in <2 days (ADR-007)

## Next Steps

1. **Review**: Engineering team reviews all ADRs, identifies gaps
2. **Prioritize**: Product ranks features (labeling UI > admin dashboard > offline)
3. **Implement**: Follow phase 1-3 plan above
4. **Iterate**: Update ADRs as design evolves (mark superseded, add new ADRs)

## References

- Buildout Plan: `/home/home/p/g/North-Shore-AI/docs/20251201/ingot.md`
- NSAI Monorepo: `/home/home/p/g/North-Shore-AI/CLAUDE.md`
- ADR Directory: `/home/home/p/g/North-Shore-AI/ingot/docs/20251201/adrs/`

---

**Total Documentation**: ~6,000 lines across 11 files
**Estimated Read Time**: 3-4 hours for complete review
**Recommended Order**: README → 001 → 002 → 005 (core flow), then others as needed
