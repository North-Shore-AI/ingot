# Ingot

<p align="center"><img src="assets/ingot.svg" alt="Ingot Logo" width="392" /></p>

[![Hex.pm](https://img.shields.io/hexpm/v/ingot.svg)](https://hex.pm/packages/ingot)
[![Documentation](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/ingot)
[![Downloads](https://img.shields.io/hexpm/dt/ingot.svg)](https://hex.pm/packages/ingot)
[![License](https://img.shields.io/github/license/North-Shore-AI/ingot.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/github-North--Shore--AI%2Fingot-blue?logo=github)](https://github.com/North-Shore-AI/ingot)

Ingot is a **composable Phoenix LiveView labeling feature module** that can be embedded in any Phoenix application. Built on top of [Forge](https://hex.pm/packages/forge_ex) and [Anvil](https://hex.pm/packages/anvil_ex), it provides a portable labeling interface with pluggable backends.

In a world already full of perfectly good data labeling tools, Ingot is the one that runs on the BEAM *and* can be mounted in your existing Phoenix app with a single router macro.

---

## What is Ingot?

Ingot is a **composable feature library** providing labeling UI for Elixir/Phoenix applications. It consists of:

- **[Forge](https://hex.pm/packages/forge_ex)** integration – creates and manages *samples* via pipelines
- **[Anvil](https://hex.pm/packages/anvil_ex)** integration – manages human labeling queues, assignments, labels, and agreements
- **Host-agnostic LiveViews** – portable labeling interface using `Phoenix.LiveView` directly
- **Backend behaviour** – pluggable data layer (use Anvil, Ecto, HTTP API, or in-memory)
- **Router macro** – mount labeling routes with `labeling_routes/2`

Ingot's job is to:

- Provide portable labeling UIs that work in any Phoenix app
- Render labeling interfaces from label schemas
- Enable custom sample/form rendering via component behaviours
- Stay out of the way of your business logic

Think of it as a **feature module** you can drop into any Phoenix app, similar to `phoenix_live_dashboard` or `oban_web`.

---

## Quick Start

### Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:ingot, "~> 0.2.0"}
  ]
end
```

### 1. Implement Backend

```elixir
defmodule MyApp.LabelingBackend do
  @behaviour Ingot.Labeling.Backend

  @impl true
  def get_next_assignment(queue_id, user_id, opts) do
    # Your implementation
  end

  @impl true
  def submit_label(assignment_id, label, opts) do
    # Your implementation
  end

  @impl true
  def get_queue_stats(queue_id, opts) do
    # Your implementation
  end
end
```

Or use the Anvil adapter:

```elixir
# Use Ingot.Labeling.AnvilClientBackend if you have Anvil configured
```

### 2. Mount Routes

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

### 3. Start Labeling

- Visit `/labeling` for the dashboard
- Visit `/labeling/queues/:queue_id/label` to start labeling

See `example/` for a complete working example.

---

## Features

### LiveView Labeling Interface

- Schema-driven UI from Anvil label definitions
- Real-time updates via LiveView and PubSub
- Keyboard-first labeling (minimal mouse usage)
- Skip / flagging for problematic samples
- Optional per-sample timing and basic analytics

### Admin & Monitoring

- Queue and pipeline status pages
- Labeler activity and velocity
- Agreement metrics surface (Cohen/Fleiss/… via Anvil)
- Export hooks for downstream training / analysis

### Workflow Characteristics

- Stateless HTTP on the edge, supervised processes underneath
- Backed by Forge samples and Anvil queues
- Plays nicely with your existing Elixir stack, telemetry, and job runners

---

## When to Use Ingot

You might want Ingot if:

- You already use or want to use **Forge** and **Anvil**
- You want a **self-hosted**, Elixir-native labeling UI
- You prefer **LiveView** over a separate SPA frontend
- You enjoy the perverse satisfaction of saying _“yes, our data labeling platform is written in Elixir”_ and having it be factually correct

You probably *don’t* want Ingot if you just need a generic labeling SaaS in five minutes. There are plenty of those.

---

## Installation

### Prerequisites

- Elixir **1.15+**
- Erlang/OTP **26+**
- Node.js **18+** (for asset compilation)
- `forge` and `anvil` from Hex (`~> 0.1.0`)

### Setup

```bash
git clone https://github.com/North-Shore-AI/ingot.git
cd ingot
```

Install dependencies:

```bash
mix setup
```

Start the Phoenix server:

```bash
mix phx.server
# or
iex -S mix phx.server
```

Then open [`http://localhost:4000`](http://localhost:4000).

---

## Configuration

Application configuration lives under `config/`.

Key options:

```elixir
# config/config.exs
config :ingot,
  # Session timeout in milliseconds
  session_timeout: :timer.hours(2),

  # Maximum samples per labeling session
  max_samples_per_session: 500,

  # Enable/disable keyboard shortcuts
  keyboard_shortcuts_enabled: true
```

You’ll also need to configure Forge and Anvil (pipelines, queues, label schemas) in your umbrella or host application.

### Connecting to Forge and Anvil

Ingot talks to Forge/Anvil through configurable client adapters:

- **HTTP (default)** – In `config/config.exs` and `prod.exs`, adapters are set to `Ingot.ForgeClient.HTTPAdapter` / `Ingot.AnvilClient.HTTPAdapter`. You must run Forge and Anvil with their Plug/Cowboy servers enabled (Forge defaults to port `4102`, Anvil to `4101`) and set `forge_base_url` / `anvil_base_url` and timeouts.
- **Elixir (in-VM)** – To call the libraries directly inside the same BEAM, include the deps as runtime (remove `optional: true, runtime: false` for `forge_ex` / `anvil_ex` in your app’s `mix.exs`) and set:

  ```elixir
  # config/runtime.exs
  config :ingot,
    forge_client_adapter: Ingot.ForgeClient.ElixirAdapter,
    anvil_client_adapter: Ingot.AnvilClient.ElixirAdapter
  ```

  In this mode you don’t need the HTTP URLs, but you do need to start the Forge/Anvil apps in the same VM.
- **Mock** – In tests, `config/test.exs` points to mock adapters; no services required.

Pick one path per environment and ensure the corresponding services (HTTP) or deps/apps (Elixir) are available.

---

## Usage

### 1. Define Samples and Queues

In your Elixir app (outside Ingot):

* Use **Forge** to define pipelines and produce samples.
* Use **Anvil** to define label schemas and queues referencing those samples.

Ingot doesn’t care about the domain; it just talks to Forge/Anvil.

### 2. Labeling Flow (Labeler View)

By default:

1. Navigate to `/label`
2. Ingot fetches the next assignment from Anvil
3. LiveView renders the form derived from the label schema
4. Labeler completes fields / ratings (keyboard shortcuts where enabled)
5. Submit → Ingot writes labels via Anvil → next assignment

Typical keyboard shortcuts (configurable):

* `1–5` – quick rating on focused dimension
* `Tab` – move between fields
* `Enter` – submit
* `S` – skip sample
* `Q` – end session

### 3. Admin Flow

Navigate to `/dashboard` to:

* Inspect queue depth and throughput
* See active labelers and recent activity
* View basic agreement metrics exposed by Anvil
* Trigger or link out to exports for downstream pipelines

---

## Project Structure

```text
ingot/
├── lib/
│   ├── ingot/
│   │   └── application.ex          # Application supervisor
│   └── ingot_web/
│       ├── components/
│       │   └── core_components.ex  # Shared UI components
│       ├── live/
│       │   ├── labeling_live.ex    # Labeling interface
│       │   ├── dashboard_live.ex   # Admin dashboard
│       │   └── components/
│       │       ├── sample_component.ex
│       │       ├── label_form_component.ex
│       │       └── progress_component.ex
│       ├── router.ex               # Routes
│       └── endpoint.ex             # Phoenix endpoint
├── assets/                         # Frontend assets
├── docs/
│   └── adrs/                       # Architecture decision records
└── test/
    └── ingot_web/
        └── live/                   # LiveView tests
```

---

## Testing

Run the test suite:

```bash
mix test
```

With coverage:

```bash
mix test --cover
```

Precommit-style checks (format, compile, test) if wired:

```bash
mix precommit
```

---

## Architecture Notes

Detailed decisions live in `docs/adrs/`, including:

* Thin wrapper architecture over Forge/Anvil
* LiveView-first UI design
* Session management and time tracking
* Real-time updates via PubSub
* Integration boundaries with Forge and Anvil

The short version: Phoenix only does presentation and request orchestration; the actual thinking happens in the libraries.

---

## Dependencies

* **Phoenix** – Web framework
* **Phoenix LiveView** – Real-time UI
* **Forge** (`~> 0.1.0` via Hex) – Sample generation and pipelines
* **Anvil** (`~> 0.1.0` via Hex) – Labeling queues, labels, agreements

---

## Contributing

If you, too, feel that the universe needed a BEAM-native data labeling UI:

1. Fork the repo
2. Create a branch: `git checkout -b feature/thing`
3. Make changes
4. Run tests: `mix precommit` (or at least `mix test`)
5. Open a PR

---

## License

Copyright (c) 2025 North Shore AI

This project is part of the North Shore AI organization.

---

## Links

* Ingot: [https://github.com/North-Shore-AI/ingot](https://github.com/North-Shore-AI/ingot)
* Forge: [https://github.com/North-Shore-AI/forge](https://github.com/North-Shore-AI/forge)
* Anvil: [https://github.com/North-Shore-AI/anvil](https://github.com/North-Shore-AI/anvil)
* Phoenix: [https://www.phoenixframework.org/](https://www.phoenixframework.org/)
* Phoenix LiveView: [https://hexdocs.pm/phoenix_live_view/](https://hexdocs.pm/phoenix_live_view/)

For questions or support, please open an issue on GitHub.
