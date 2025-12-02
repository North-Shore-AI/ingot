import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ingot start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ingot, IngotWeb.Endpoint, server: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "ingot.nsai.io"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ingot, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ingot, IngotWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Database Configuration (optional - Ingot is stateless by default)
  # If DATABASE_URL is provided, configure Ecto
  if database_url = System.get_env("DATABASE_URL") do
    config :ingot, Ingot.Repo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      ssl: System.get_env("DATABASE_SSL") == "true"
  end

  # Forge Client Configuration
  config :ingot,
    forge_base_url: System.get_env("FORGE_URL"),
    forge_timeout: String.to_integer(System.get_env("FORGE_TIMEOUT_MS") || "5000")

  # Anvil Client Configuration
  config :ingot,
    anvil_base_url: System.get_env("ANVIL_URL"),
    anvil_timeout: String.to_integer(System.get_env("ANVIL_TIMEOUT_MS") || "5000")

  # OIDC Authentication Configuration (optional)
  if oidc_client_id = System.get_env("OIDC_CLIENT_ID") do
    config :ingot, :oidc,
      provider:
        System.get_env("OIDC_PROVIDER") ||
          raise("OIDC_PROVIDER is required when OIDC_CLIENT_ID is set"),
      client_id: oidc_client_id,
      client_secret:
        System.get_env("OIDC_CLIENT_SECRET") ||
          raise("OIDC_CLIENT_SECRET is required when OIDC_CLIENT_ID is set"),
      redirect_uri: System.get_env("OIDC_REDIRECT_URI", "https://#{host}/auth/callback")
  end

  # AWS S3 Configuration (for artifact URLs - optional)
  if access_key_id = System.get_env("AWS_ACCESS_KEY_ID") do
    config :ex_aws,
      access_key_id: access_key_id,
      secret_access_key:
        System.get_env("AWS_SECRET_ACCESS_KEY") ||
          raise("AWS_SECRET_ACCESS_KEY is required when AWS_ACCESS_KEY_ID is set"),
      region: System.get_env("AWS_REGION", "us-east-1")
  end

  # Telemetry Configuration
  config :ingot, :telemetry,
    prometheus_enabled: System.get_env("PROMETHEUS_ENABLED", "true") == "true",
    log_level: String.to_atom(System.get_env("LOG_LEVEL") || "info")

  # Logging Configuration
  config :logger,
    level: String.to_atom(System.get_env("LOG_LEVEL") || "info")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ingot, IngotWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ingot, IngotWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
