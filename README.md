# Ingot

<p align="center"><img src="assets/ingot.svg" alt="Ingot Logo" width="392" /></p>

[![Hex.pm](https://img.shields.io/hexpm/v/ingot.svg)](https://hex.pm/packages/ingot)
[![Documentation](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/ingot)
[![Downloads](https://img.shields.io/hexpm/dt/ingot.svg)](https://hex.pm/packages/ingot)
[![License](https://img.shields.io/github/license/North-Shore-AI/ingot.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/github-North--Shore--AI%2Fingot-blue?logo=github)](https://github.com/North-Shore-AI/ingot)

Ingot is a Phoenix LiveView application for **sample generation** and **human labeling workflows**, built on top of [Forge](https://hex.pm/packages/forge_ex) and [Anvil](https://hex.pm/packages/anvil_ex).

In a world already full of perfectly good data labeling tools, Ingot is the one that runs on the BEAM for reasons that, in hindsight, appear to be *intentional*.

---

## What is Ingot?

Ingot is a **thin web shell** around two Elixir libraries:

- **[Forge](https://hex.pm/packages/forge_ex)** – creates and manages *samples* via pipelines
- **[Anvil](https://hex.pm/packages/anvil_ex)** – manages human labeling queues, assignments, labels, and agreements

Ingot’s job is to:

- Render labeling UIs (via LiveView) from Anvil label schemas
- Surface pipelines, queues, and agreement metrics in a browser
- Handle sessions, auth, and user flows for labelers and admins
- Stay out of the way of your actual business logic

Think of it as the **UI layer** that turns Forge + Anvil into a usable product, without smuggling any domain logic into Phoenix.

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
