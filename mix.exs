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
      docs: docs()
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
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1"},
      {:bandit, "~> 1.5"},
      {:forge_ex, "~> 0.1", optional: true},
      {:anvil_ex, "~> 0.1", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
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
      files: ~w(lib priv assets .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
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
end
