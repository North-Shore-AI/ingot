# Ingot Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the Ingot repository. These documents capture key architectural decisions made during the design and implementation of Ingot as a Phoenix LiveView interface for sample generation and human labeling workflows.

## Overview

Ingot serves as a thin UI layer over two core services:
- **Forge**: Sample generation factory (pipelines, samples, artifacts)
- **Anvil**: Labeling queue manager (assignments, labels, agreement metrics)

## ADR Index

### Core Architecture

| ADR | Title | Status | Summary |
|-----|-------|--------|---------|
| [001](001-stateless-ui-architecture.md) | Stateless UI Architecture | Accepted | Ingot as thin stateless layer with no domain data ownership, delegates to Forge/Anvil |
| [002](002-client-layer-design.md) | Client Layer Design | Accepted | ForgeClient and AnvilClient modules with DTO layer, error handling, resilience patterns |
| [004](004-persistence-strategy.md) | Persistence Strategy | Accepted | Single Postgres cluster with separate schemas, shared MinIO/S3, no per-repo instances |

### User Experience

| ADR | Title | Status | Summary |
|-----|-------|--------|---------|
| [005](005-realtime-ux.md) | Realtime UX | Accepted | LiveView with PubSub for progress tracking, keyboard shortcuts, mobile responsiveness |
| [006](006-admin-dashboard.md) | Admin Dashboard | Accepted | Queue controls, agreement visualization, label review, export management, audit logs |
| [007](007-pluggable-components.md) | Pluggable Components | Accepted | Runtime-registered components for domain-specific UIs (CNS as first example) |

### Security & Auth

| ADR | Title | Status | Summary |
|-----|-------|--------|---------|
| [003](003-auth-strategy.md) | Auth Strategy | Accepted | OIDC for internal users, invite codes for external labelers, roles stored in Anvil |

### Operations

| ADR | Title | Status | Summary |
|-----|-------|--------|---------|
| [008](008-telemetry-observability.md) | Telemetry & Observability | Accepted | Telemetry integration, Prometheus metrics, distributed tracing, structured logging |
| [009](009-deployment-packaging.md) | Deployment & Packaging | Accepted | OTP release with Docker containerization, K8s deployment, ENV-based config |
| [010](010-offline-and-pwa.md) | Offline & PWA Support | Proposed | Online-only with optimistic UI for now, offline PWA reserved for future use cases |

## ADR Status Definitions

- **Proposed**: Under discussion, not yet implemented
- **Accepted**: Decision made, implementation in progress or complete
- **Deprecated**: No longer valid, superseded by another ADR
- **Superseded**: Replaced by a newer ADR (link provided)

## Reading Guide

**For New Engineers:**
1. Start with ADR-001 (Stateless UI Architecture) to understand core principles
2. Read ADR-002 (Client Layer Design) to understand Forge/Anvil integration
3. Read ADR-005 (Realtime UX) to understand LiveView patterns

**For Frontend Developers:**
- ADR-005: Realtime UX (LiveView, PubSub, keyboard shortcuts)
- ADR-007: Pluggable Components (custom UI components)
- ADR-010: Offline & PWA (optimistic UI, future offline support)

**For Backend Developers:**
- ADR-002: Client Layer Design (ForgeClient, AnvilClient)
- ADR-004: Persistence Strategy (database schemas, blob storage)
- ADR-008: Telemetry & Observability (metrics, tracing)

**For DevOps/SRE:**
- ADR-009: Deployment & Packaging (Docker, K8s, secrets management)
- ADR-008: Telemetry & Observability (health checks, Prometheus)

**For Product/Research Teams:**
- ADR-001: Stateless UI Architecture (what Ingot does/doesn't do)
- ADR-006: Admin Dashboard (queue management, label review)
- ADR-007: Pluggable Components (adding domain-specific UIs)

## Architectural Principles

Based on the ADRs, Ingot follows these core principles:

1. **Statelessness**: Ingot does not persist domain data. All samples/labels live in Forge/Anvil.
2. **Delegation**: Business logic lives in domain services, Ingot focuses on presentation.
3. **Real-Time**: LiveView + PubSub provide instant feedback without full page reloads.
4. **Extensibility**: Pluggable components allow domain-specific UIs without core changes.
5. **Observability**: Comprehensive telemetry for debugging, monitoring, and compliance.
6. **Security**: OIDC auth, role-based access, CSP headers, encrypted sessions.
7. **Scalability**: Horizontal scaling via stateless nodes, sticky sessions for LiveView.

## Contributing New ADRs

When adding a new ADR:

1. Copy the template from an existing ADR
2. Use sequential numbering (011, 012, etc.)
3. Include these sections:
   - **Status**: Proposed | Accepted | Deprecated | Superseded
   - **Context**: Problem statement, background, constraints
   - **Decision**: What was decided and why
   - **Consequences**: Positive, Negative, Neutral outcomes
4. Link related ADRs at the end
5. Update this README index

## References

- [Buildout Plan](/home/home/p/g/North-Shore-AI/docs/20251201/ingot.md)
- [North-Shore-AI Monorepo README](/home/home/p/g/North-Shore-AI/CLAUDE.md)
- [ADR Template](https://github.com/joelparkerhenderson/architecture-decision-record)

## Questions?

For questions about these ADRs or Ingot architecture:
- Open an issue in the Ingot repository
- Tag `@ingot-team` in discussions
- Consult the buildout plan for additional context
