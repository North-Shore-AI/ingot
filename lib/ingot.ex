defmodule Ingot do
  @moduledoc """
  Composable Phoenix LiveView labeling feature module.

  Ingot is a portable labeling interface that can be embedded in any Phoenix
  application. It provides LiveViews, component behaviours, and a backend
  abstraction for flexible data storage.

  ## Key Features

  - **Composable Router Macro** - Mount labeling routes with `labeling_routes/2`
  - **Pluggable Backend** - Implement `Ingot.Labeling.Backend` for any data source
  - **Customizable Components** - Extend `Ingot.SampleRenderer` and `Ingot.LabelFormRenderer`
  - **Real-time Updates** - Phoenix PubSub integration for live progress tracking
  - **Forge/Anvil Integration** - Built-in adapters for Forge samples and Anvil queues

  ## Quick Start

  See `Ingot.Labeling` for installation and usage instructions.

  ## Architecture

  Ingot is organized into several subsystems:

  - `Ingot.Labeling` - Main feature module with LiveViews and router
  - `Ingot.ForgeClient` - Thin wrapper for Forge sample API
  - `Ingot.AnvilClient` - Thin wrapper for Anvil queue/label API
  - `Ingot.Progress` - PubSub broadcasting for real-time updates
  - `Ingot.Components` - Sample and label form rendering behaviours

  ## Philosophy

  Ingot is designed as a **feature module** that integrates into existing
  Phoenix applications, similar to `phoenix_live_dashboard` or `oban_web`.
  It doesn't impose database schemas or business logic - you provide the
  backend implementation that fits your domain.
  """
end
