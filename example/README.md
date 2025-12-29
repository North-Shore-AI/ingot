# Ingot Example App

This is a minimal Phoenix application demonstrating how to use the Ingot labeling feature module in a host application.

## Key Concepts

This example shows:

1. **Backend Implementation** - See `lib/ingot_example/labeling_backend.ex` for how to implement `Ingot.Labeling.Backend`
2. **Router Integration** - See `lib/ingot_example_web/router.ex` for how to mount labeling routes
3. **Minimal Dependencies** - The example app only depends on the parent `ingot` project

## Running the Example

```bash
# From the example/ directory
mix deps.get
mix phx.server
```

Visit `http://localhost:4000/labeling` to see the dashboard.

Visit `http://localhost:4000/labeling/queues/example-queue/label` to start labeling.

## Project Structure

```
example/
├── lib/
│   ├── ingot_example/
│   │   ├── application.ex           # Application supervisor
│   │   └── labeling_backend.ex      # Backend implementation
│   └── ingot_example_web/
│       └── router.ex                # Router with labeling_routes
├── mix.exs                          # Depends on parent ingot project
└── README.md
```

## Customization

To customize the labeling interface for your domain:

1. Implement `Ingot.SampleRenderer` for custom sample visualization
2. Implement `Ingot.LabelFormRenderer` for custom label input widgets
3. Pass custom components via the assignment metadata

See the main Ingot documentation for details.
