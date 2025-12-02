defmodule Ingot.Auth.OIDCTest do
  use ExUnit.Case, async: true

  alias Ingot.Auth.OIDC

  describe "authorization_url/2" do
    test "generates authorization URL with required parameters" do
      config = %{
        provider: "https://auth.example.com",
        client_id: "test_client",
        redirect_uri: "https://ingot.test/auth/callback",
        scopes: ["openid", "email", "profile"]
      }

      state = "random_state_123"

      url = OIDC.authorization_url(config, state)

      assert url =~ "https://auth.example.com/authorize"
      assert url =~ "client_id=test_client"
      assert url =~ "redirect_uri=https%3A%2F%2Fingot.test%2Fauth%2Fcallback"
      assert url =~ "response_type=code"
      assert url =~ "scope=openid+email+profile"
      assert url =~ "state=#{state}"
    end

    test "supports custom provider endpoints" do
      config = %{
        provider: "https://custom.provider.com",
        client_id: "client_123",
        redirect_uri: "https://app.test/callback",
        scopes: ["openid"]
      }

      url = OIDC.authorization_url(config, "state")

      assert url =~ "https://custom.provider.com/authorize"
    end
  end

  describe "exchange_code/2" do
    test "returns success with mock token response" do
      config = %{
        provider: "https://auth.example.com",
        client_id: "test_client",
        client_secret: "test_secret",
        redirect_uri: "https://ingot.test/auth/callback"
      }

      code = "auth_code_123"

      # Mock implementation will return a fake token
      assert {:ok, token_response} = OIDC.exchange_code(config, code)
      assert is_map(token_response)
      assert Map.has_key?(token_response, "access_token")
      assert Map.has_key?(token_response, "id_token")
      assert Map.has_key?(token_response, "token_type")
    end
  end

  describe "verify_id_token/2" do
    test "extracts claims from valid mock token" do
      config = %{provider: "https://auth.example.com"}
      id_token = "mock.jwt.token"

      assert {:ok, claims} = OIDC.verify_id_token(config, id_token)
      assert is_map(claims)
      assert Map.has_key?(claims, "sub")
      assert Map.has_key?(claims, "email")
    end

    test "returns error for empty token" do
      config = %{provider: "https://auth.example.com"}

      assert {:error, :invalid_token} = OIDC.verify_id_token(config, "")
      assert {:error, :invalid_token} = OIDC.verify_id_token(config, nil)
    end
  end

  describe "provider_configs/0" do
    test "returns configurations for supported providers" do
      configs = OIDC.provider_configs()

      assert is_map(configs)
      assert Map.has_key?(configs, :auth0)
      assert Map.has_key?(configs, :okta)
      assert Map.has_key?(configs, :keycloak)

      # Verify structure
      auth0_config = configs.auth0
      assert Map.has_key?(auth0_config, :authorize_endpoint)
      assert Map.has_key?(auth0_config, :token_endpoint)
      assert Map.has_key?(auth0_config, :userinfo_endpoint)
    end
  end
end
