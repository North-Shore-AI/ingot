defmodule Ingot.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/North-Shore-AI/ingot"

  def project do
    [
      app: :ingot,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      package: package(),
      name: "Ingot",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      dialyzer: dialyzer(),
      releases: releases()
    ]
  end

  def application do
    [
      mod: {Ingot.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20 or ~> 1.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1"},
      {:bandit, "~> 1.5"},
      {:ecto_sql, "~> 3.10", optional: true, runtime: false},
      {:postgrex, "~> 0.17", optional: true, runtime: false},
      {:oban, "~> 2.17", optional: true, runtime: false},
      {:cachex, "~> 3.6", optional: true, runtime: false},
      {:fuse, "~> 2.5", optional: true, runtime: false},
      {:httpoison, "~> 2.2", optional: true, runtime: false},
      {:forge, "~> 0.1.0", hex: :forge_ex, optional: true, runtime: false},
      {:anvil, "~> 0.1.0", hex: :anvil_ex, optional: true, runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:supertester, "~> 0.3.1", only: :test}
    ]
  end

  defp description do
    """
    Phoenix LiveView interface for sample generation and human labeling
    workflows. Thin wrapper around Forge (sample factory) and Anvil
    (labeling queue) with real-time progress updates, keyboard shortcuts,
    and inter-rater reliability dashboards.
    """
  end

  defp package do
    [
      name: "ingot",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["North-Shore-AI"],
      files:
        ~w(lib priv assets assets/ingot.svg .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      assets: %{"assets" => "assets"},
      logo: "assets/ingot.svg",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Ingot,
          Ingot.Application
        ],
        Clients: [
          Ingot.ForgeClient,
          Ingot.AnvilClient,
          Ingot.Progress
        ],
        "Live Views": [
          IngotWeb.LabelingLive,
          IngotWeb.DashboardLive
        ],
        Components: [
          IngotWeb.SampleComponent,
          IngotWeb.LabelFormComponent,
          IngotWeb.ProgressComponent
        ]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind ingot", "esbuild ingot"],
      "assets.deploy": [
        "tailwind ingot --minify",
        "esbuild ingot --minify",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit, :ecto, :ecto_sql],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp releases do
    [
      ingot: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
