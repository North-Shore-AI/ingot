# Ingot

![Ingot Logo](assets/ingot.svg)

[![GitHub](https://img.shields.io/badge/github-North--Shore--AI%2Fingot-blue)](https://github.com/North-Shore-AI/ingot)

A Phoenix LiveView interface for sample generation and human labeling workflows. Ingot provides a thin, elegant wrapper around the [Forge](../forge) and [Anvil](../anvil) libraries, exposing their functionality through an intuitive web interface.

## Purpose

Ingot is designed as a **minimal, thin wrapper** that:

- Provides a web-based interface for human labeling tasks
- Delegates all business logic to Forge (sample generation) and Anvil (label storage)
- Manages user sessions and labeling workflows
- Displays real-time progress and queue status
- Offers keyboard shortcuts for efficient labeling

**Design Philosophy**: Ingot contains minimal logic itself. It orchestrates calls to Forge and Anvil, focusing exclusively on presentation and user interaction.

## Features

### LiveView Labeling Interface
- **Real-time labeling UI**: Rate narrative synthesis samples on multiple dimensions
- **Keyboard shortcuts**: Navigate and label efficiently without touching the mouse
- **Progress tracking**: See your labeling progress in real-time
- **Skip functionality**: Skip problematic or ambiguous samples
- **Timer tracking**: Record time spent on each labeling task

### Rating Dimensions
- **Coherence**: How well does the synthesis integrate both narratives?
- **Grounded**: Is the synthesis supported by the source narratives?
- **Novel**: Does the synthesis add new insights beyond simple summary?
- **Balanced**: Does the synthesis give fair weight to both perspectives?

### Admin Dashboard
- View overall labeling statistics
- Monitor queue progress
- Track labeler performance
- Export labeled data

### Real-time Updates
- Phoenix PubSub for live progress updates
- Automatic UI refresh when new samples are available
- Real-time labeler count display

## Installation

### Prerequisites

- Elixir 1.15 or later
- Erlang/OTP 26 or later
- Node.js 18+ (for asset compilation)
- Forge and Anvil libraries (sibling directories)

### Setup

1. Clone the repository:
```bash
git clone https://github.com/North-Shore-AI/ingot.git
cd ingot
```

2. Install dependencies:
```bash
mix setup
```

3. Start the Phoenix server:
```bash
mix phx.server
```

4. Visit [`localhost:4000`](http://localhost:4000) in your browser.

Alternatively, run inside IEx for debugging:
```bash
iex -S mix phx.server
```

## Configuration

Configuration options are available in `config/`:

- `config/config.exs` - General application configuration
- `config/dev.exs` - Development environment settings
- `config/prod.exs` - Production environment settings
- `config/test.exs` - Test environment settings

### Key Configuration Options

```elixir
# config/config.exs
config :ingot,
  # Session timeout in milliseconds
  session_timeout: :timer.hours(2),

  # Maximum samples per session
  max_samples_per_session: 500,

  # Enable/disable keyboard shortcuts
  keyboard_shortcuts_enabled: true
```

## Usage

### Labeling Workflow

1. Navigate to the labeling interface at `/label`
2. Review the two source narratives (A and B)
3. Read the synthesis text
4. Rate the synthesis on each dimension (1-5 scale)
5. Optionally add notes in the text field
6. Submit and proceed to the next sample

### Keyboard Shortcuts

- **1-5**: Quick rating for focused dimension
- **Tab**: Navigate between rating dimensions
- **Enter**: Submit current label and load next sample
- **S**: Skip current sample
- **Q**: Quit labeling session

### Admin Dashboard

Access the admin dashboard at `/dashboard` to:

- View total labeled samples
- Monitor active labelers
- Check queue depth
- Export labeled datasets
- View labeling velocity metrics

## Screenshots

> Coming soon

## Testing

Run the full test suite:

```bash
mix test
```

Run tests with coverage:

```bash
mix test --cover
```

Run precommit checks (compile, format, test):

```bash
mix precommit
```

## Architecture

See [Architecture Decision Records](docs/adrs/) for detailed design decisions:

- [ADR-001: Thin Wrapper Architecture](docs/adrs/001-thin-wrapper-architecture.md)
- [ADR-002: LiveView Labeling Interface Design](docs/adrs/002-liveview-labeling-interface.md)
- [ADR-003: Session Management Strategy](docs/adrs/003-session-management.md)
- [ADR-004: Real-time Progress Updates](docs/adrs/004-realtime-progress-updates.md)
- [ADR-005: Keyboard Shortcuts for Labeling](docs/adrs/005-keyboard-shortcuts.md)
- [ADR-006: Integration with Forge and Anvil](docs/adrs/006-forge-anvil-integration.md)

## Project Structure

```
ingot/
├── lib/
│   ├── ingot/
│   │   └── application.ex          # Application supervisor
│   └── ingot_web/
│       ├── components/
│       │   └── core_components.ex  # Shared UI components
│       ├── live/
│       │   ├── labeling_live.ex    # Main labeling interface
│       │   ├── dashboard_live.ex   # Admin dashboard
│       │   └── components/
│       │       ├── sample_component.ex
│       │       ├── label_form_component.ex
│       │       └── progress_component.ex
│       ├── router.ex               # Route definitions
│       └── endpoint.ex             # Phoenix endpoint
├── test/
│   └── ingot_web/
│       └── live/                   # LiveView tests
├── docs/
│   └── adrs/                       # Architecture decisions
└── assets/                         # Frontend assets
```

## Dependencies

- **Phoenix**: Web framework
- **Phoenix LiveView**: Real-time UI components
- **Forge**: Sample generation library (path dependency)
- **Anvil**: Label storage library (path dependency)
- **Supertester**: Enhanced testing framework

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`mix precommit`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

Copyright (c) 2025 North Shore AI

This project is part of the North Shore AI organization.

## Links

- **GitHub**: https://github.com/North-Shore-AI/ingot
- **Forge**: https://github.com/North-Shore-AI/forge
- **Anvil**: https://github.com/North-Shore-AI/anvil
- **Phoenix Framework**: https://www.phoenixframework.org/
- **Phoenix LiveView**: https://hexdocs.pm/phoenix_live_view/

## Contact

For questions or support, please open an issue on GitHub.
