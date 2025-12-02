defmodule Ingot.Auth.OIDC do
  @moduledoc """
  OpenID Connect (OIDC) authentication provider.

  Supports multiple OIDC providers including Auth0, Okta, and Keycloak.
  This is a stub implementation suitable for testing and development.
  Production deployments should integrate with a real OIDC library.

  ## Configuration

  OIDC configuration should include:

      config = %{
        provider: "https://auth.example.com",
        client_id: "your_client_id",
        client_secret: "your_client_secret",
        redirect_uri: "https://your-app.com/auth/callback",
        scopes: ["openid", "email", "profile"]
      }

  ## Supported Providers

  - Auth0 (auth0.com)
  - Okta (okta.com)
  - Keycloak (keycloak.org)
  - Generic OIDC-compliant providers

  ## Examples

      # Generate authorization URL
      config = %{provider: "https://auth.example.com", client_id: "client_123", ...}
      url = OIDC.authorization_url(config, "random_state")

      # Exchange authorization code for tokens
      {:ok, tokens} = OIDC.exchange_code(config, "auth_code_123")

      # Verify and extract claims from ID token
      {:ok, claims} = OIDC.verify_id_token(config, tokens["id_token"])
  """

  @type config :: %{
          required(:provider) => String.t(),
          required(:client_id) => String.t(),
          required(:client_secret) => String.t(),
          required(:redirect_uri) => String.t(),
          required(:scopes) => [String.t()]
        }

  @type token_response :: %{
          String.t() => String.t()
        }

  @type claims :: %{
          String.t() => term()
        }

  @doc """
  Generate OIDC authorization URL.

  Returns a URL that the user should be redirected to for authentication.

  ## Parameters

    - `config` - OIDC configuration map
    - `state` - Random state parameter for CSRF protection

  ## Examples

      iex> config = %{provider: "https://auth.example.com", client_id: "client_123", redirect_uri: "https://app/callback", scopes: ["openid"]}
      iex> url = OIDC.authorization_url(config, "state_xyz")
      iex> String.contains?(url, "client_id=client_123")
      true
  """
  @spec authorization_url(config(), String.t()) :: String.t()
  def authorization_url(config, state) do
    provider_config = get_provider_config(config.provider)

    params =
      URI.encode_query(%{
        client_id: config.client_id,
        redirect_uri: config.redirect_uri,
        response_type: "code",
        scope: Enum.join(config.scopes, " "),
        state: state
      })

    "#{provider_config.authorize_endpoint}?#{params}"
  end

  @doc """
  Exchange authorization code for tokens.

  This is a stub implementation that returns mock tokens.
  In production, this would make an HTTP request to the token endpoint.

  ## Parameters

    - `config` - OIDC configuration map
    - `code` - Authorization code from callback

  ## Examples

      iex> config = %{provider: "https://auth.example.com", client_id: "client_123", client_secret: "secret", redirect_uri: "https://app/callback"}
      iex> {:ok, tokens} = OIDC.exchange_code(config, "auth_code_123")
      iex> Map.has_key?(tokens, "access_token")
      true
  """
  @spec exchange_code(config(), String.t()) :: {:ok, token_response()} | {:error, atom()}
  def exchange_code(_config, code) when is_binary(code) and byte_size(code) > 0 do
    # Stub implementation - returns mock tokens
    # In production, this would make an HTTP POST to the token endpoint
    {:ok,
     %{
       "access_token" => "mock_access_token_#{:rand.uniform(1000)}",
       "id_token" => "mock.id.token",
       "token_type" => "Bearer",
       "expires_in" => 3600
     }}
  end

  def exchange_code(_config, _code), do: {:error, :invalid_code}

  @doc """
  Verify ID token and extract claims.

  This is a stub implementation that returns mock claims.
  In production, this would verify the JWT signature and extract claims.

  ## Parameters

    - `config` - OIDC configuration map
    - `id_token` - ID token from token response

  ## Examples

      iex> config = %{provider: "https://auth.example.com"}
      iex> {:ok, claims} = OIDC.verify_id_token(config, "mock.jwt.token")
      iex> Map.has_key?(claims, "sub")
      true
  """
  @spec verify_id_token(config(), String.t()) :: {:ok, claims()} | {:error, :invalid_token}
  def verify_id_token(_config, id_token) when is_binary(id_token) and byte_size(id_token) > 0 do
    # Stub implementation - returns mock claims
    # In production, this would:
    # 1. Verify JWT signature using provider's public key
    # 2. Verify issuer, audience, expiration
    # 3. Extract claims
    {:ok,
     %{
       "sub" => "oidc_user_#{:rand.uniform(10000)}",
       "email" => "user#{:rand.uniform(100)}@example.com",
       "name" => "Test User",
       "email_verified" => true,
       "iat" => DateTime.utc_now() |> DateTime.to_unix(),
       "exp" => DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
     }}
  end

  def verify_id_token(_config, _id_token), do: {:error, :invalid_token}

  @doc """
  Get provider-specific endpoint configurations.

  Returns a map of known OIDC providers and their endpoint URLs.

  ## Examples

      iex> configs = OIDC.provider_configs()
      iex> Map.has_key?(configs, :auth0)
      true
  """
  @spec provider_configs() :: %{atom() => map()}
  def provider_configs do
    %{
      auth0: %{
        authorize_endpoint: "/authorize",
        token_endpoint: "/oauth/token",
        userinfo_endpoint: "/userinfo",
        jwks_uri: "/.well-known/jwks.json"
      },
      okta: %{
        authorize_endpoint: "/oauth2/v1/authorize",
        token_endpoint: "/oauth2/v1/token",
        userinfo_endpoint: "/oauth2/v1/userinfo",
        jwks_uri: "/oauth2/v1/keys"
      },
      keycloak: %{
        authorize_endpoint: "/protocol/openid-connect/auth",
        token_endpoint: "/protocol/openid-connect/token",
        userinfo_endpoint: "/protocol/openid-connect/userinfo",
        jwks_uri: "/protocol/openid-connect/certs"
      }
    }
  end

  # Private helpers

  defp get_provider_config(provider_url) do
    # Detect provider type from URL or use generic endpoints
    cond do
      String.contains?(provider_url, "auth0.com") ->
        Map.merge(provider_configs().auth0, %{base_url: provider_url})

      String.contains?(provider_url, "okta.com") ->
        Map.merge(provider_configs().okta, %{base_url: provider_url})

      String.contains?(provider_url, "keycloak") ->
        Map.merge(provider_configs().keycloak, %{base_url: provider_url})

      true ->
        # Generic OIDC provider
        %{
          base_url: provider_url,
          authorize_endpoint: "#{provider_url}/authorize",
          token_endpoint: "#{provider_url}/token",
          userinfo_endpoint: "#{provider_url}/userinfo"
        }
    end
  end
end
