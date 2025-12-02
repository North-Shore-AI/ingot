# ADR-001: Thin Wrapper Architecture

## Status

Accepted

## Context

Ingot needs to provide a web interface for human labeling workflows. The core functionality for sample generation and label storage already exists in the Forge and Anvil libraries respectively. We need to decide how much business logic should live in Ingot versus delegating to existing libraries.

## Decision

Ingot will be implemented as a **thin wrapper** with minimal business logic:

- **Presentation Layer Only**: Ingot focuses exclusively on UI/UX and user interaction
- **Delegate to Libraries**: All sample generation logic delegates to Forge
- **Delegate Storage**: All label persistence delegates to Anvil
- **Orchestration**: Ingot orchestrates calls between Forge and Anvil
- **Session Management**: Ingot manages user sessions and UI state only

### What Ingot Does

- Render LiveView interfaces for labeling
- Manage user sessions and authentication
- Handle keyboard shortcuts and UI interactions
- Display real-time progress via PubSub
- Route requests to Forge and Anvil

### What Ingot Does NOT Do

- Generate samples (Forge's responsibility)
- Store labels (Anvil's responsibility)
- Validate label data beyond UI constraints
- Implement domain logic for synthesis evaluation
- Make decisions about sample selection algorithms

## Consequences

### Positive

- **Clear Separation of Concerns**: Each library has a well-defined responsibility
- **Maintainability**: Business logic changes happen in Forge/Anvil, not Ingot
- **Testability**: UI tests are isolated from business logic tests
- **Reusability**: Forge and Anvil can be used independently of Ingot
- **Simplicity**: Ingot remains small and focused

### Negative

- **Network Overhead**: More function calls between libraries
- **Dependency Management**: Ingot requires both Forge and Anvil to function
- **Debugging Complexity**: Issues may span multiple libraries

### Mitigation

- Use path dependencies for fast local development
- Implement comprehensive logging at library boundaries
- Create integration tests that span all three libraries
- Document the interaction patterns clearly

## Alternatives Considered

### 1. Monolithic Application

Implement all functionality directly in Ingot.

**Rejected because:**
- Violates separation of concerns
- Makes testing more difficult
- Reduces reusability of components

### 2. Microservices Architecture

Deploy Forge and Anvil as separate HTTP services.

**Rejected because:**
- Unnecessary complexity for local development
- Network latency impacts user experience
- Operational overhead not justified for initial version

## Implementation Notes

- Forge and Anvil are included as path dependencies in mix.exs
- Ingot modules should import Forge/Anvil functions, not reimplement them
- Code reviews should reject business logic in Ingot modules
- Integration tests should verify correct delegation to libraries

## References

- [ADR-006: Integration with Forge and Anvil](006-forge-anvil-integration.md)
- [Forge Library Documentation](../../forge/README.md)
- [Anvil Library Documentation](../../anvil/README.md)
