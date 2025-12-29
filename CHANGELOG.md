# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2025-12-06

### Breaking Changes

- **Architecture:** Restructured as composable feature library instead of standalone Phoenix app
- **LiveViews:** Now host-agnostic using `Phoenix.LiveView` directly instead of `IngotWeb`
  - Moved `IngotWeb.LabelingLive` to `Ingot.Labeling.LabelingLive`
  - Moved `IngotWeb.DashboardLive` to `Ingot.Labeling.DashboardLive`
- **Router:** Direct route definitions replaced with `labeling_routes/2` macro
- **Backend:** Requires implementing `Ingot.Labeling.Backend` behaviour for data operations

### Added

#### Core Features

- `Ingot.Labeling` module - Main feature module with comprehensive documentation
- `Ingot.Labeling.Router` macro for mounting labeling routes with single call
  - Supports `on_mount` hooks for authentication/authorization
  - Configurable `root_layout` and `session_layout`
  - Session-based configuration injection
- `Ingot.Labeling.Backend` behaviour for pluggable data layer
  - `get_next_assignment/3` - Fetch next assignment for user
  - `submit_label/3` - Submit completed label
  - `get_queue_stats/2` - Retrieve queue statistics
  - Optional `check_queue_access/3` callback for access control
- `Ingot.Labeling.AnvilClientBackend` - Reference adapter wrapping `Ingot.AnvilClient`

#### Infrastructure

- `example/` - Standalone Phoenix example app demonstrating usage
- Full test coverage for router macro and backend behaviour
- IR-driven labeling flow using shared `labeling_ir` structs
  - Tenant-aware assignments and labels
  - Lineage metadata tracking
  - Namespace support
- Componentized LiveView with queue-specific module resolution
  - Falls back to `Ingot.Components.DefaultComponent`
  - Preserves `Ingot.SampleRenderer` and `Ingot.LabelFormRenderer` behaviours

#### Documentation

- Comprehensive `@moduledoc` for all public modules
- Router macro usage examples
- Backend implementation guide
- Migration guide from v0.1.x

### Changed

- Session management now via router-injected configuration
- Component loading mechanism supports dynamic resolution
- HTTP adapters now use `Code.ensure_loaded?/1` for optional HTTPoison dependency
- Updated Phoenix.Component usage for LiveView 0.20+ compatibility

### Fixed

- Removed usage of deprecated `Phoenix.Component.used_input?/1`
- Fixed unused variable warnings in HEEx templates
- Fixed HTTPoison undefined function warnings
- Corrected template syntax in default component

### Migration Guide from v0.1.x

#### Step 1: Implement Backend Behaviour

```elixir
defmodule MyApp.LabelingBackend do
  @behaviour Ingot.Labeling.Backend

  @impl true
  def get_next_assignment(queue_id, user_id, opts) do
    # Your implementation - fetch from Ecto, HTTP API, etc.
  end

  @impl true
  def submit_label(assignment_id, label, opts) do
    # Your implementation - store label
  end

  @impl true
  def get_queue_stats(queue_id, opts) do
    # Your implementation - return %{remaining: N, labeled: M}
  end
end
```

Or use the provided Anvil adapter:

```elixir
config = %{backend: Ingot.Labeling.AnvilClientBackend}
```

#### Step 2: Update Router

**Old (0.1.x):**

```elixir
live "/queues/:queue_id/label", IngotWeb.LabelingLive, :label
live "/dashboard", IngotWeb.DashboardLive, :index
```

**New (0.2.x):**

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import Ingot.Labeling.Router

  scope "/" do
    pipe_through [:browser, :require_authenticated]

    labeling_routes "/labeling",
      on_mount: [MyAppWeb.AuthLive],
      root_layout: {MyAppWeb.Layouts, :app},
      config: %{
        backend: MyApp.LabelingBackend,
        default_queue_id: "my-queue"
      }
  end
end
```

#### Step 3: Update Component References

If you customized components, update module references:

- `IngotWeb.SampleComponent` → `Ingot.SampleRenderer` (behaviour)
- `IngotWeb.LabelFormComponent` → `Ingot.LabelFormRenderer` (behaviour)

#### Step 4: Test Routes

- Dashboard: `/labeling`
- Labeling interface: `/labeling/queues/:queue_id/label`

## [0.1.0] - 2024-12-01

### Added

- Initial release
- `IngotWeb.LabelingLive` - main labeling LiveView interface
- `IngotWeb.DashboardLive` - admin dashboard with statistics
- `IngotWeb.SampleComponent` - sample display component
- `IngotWeb.LabelFormComponent` - rating form component
- `IngotWeb.ProgressComponent` - progress bar component
- `Ingot.ForgeClient` - thin wrapper for Forge integration
- `Ingot.AnvilClient` - thin wrapper for Anvil integration
- `Ingot.Progress` - PubSub broadcasting for real-time updates
- Keyboard shortcuts for high-throughput labeling
- Real-time progress updates via Phoenix PubSub
- Session-based labeling time tracking
- Skip/quit functionality for labeling workflow
- Comprehensive test suite using Supertester

[Unreleased]: https://github.com/North-Shore-AI/ingot/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/North-Shore-AI/ingot/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/North-Shore-AI/ingot/releases/tag/v0.1.0
