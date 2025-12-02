defmodule Ingot.AuthTest do
  use ExUnit.Case, async: true

  alias Ingot.Auth

  describe "create_session/2" do
    test "creates session with user data and roles" do
      user = %{
        id: "user_123",
        email: "test@example.com",
        roles: [:labeler]
      }

      session_data = Auth.create_session(user)

      assert session_data.user_id == "user_123"
      assert session_data.user_email == "test@example.com"
      assert session_data.roles == [:labeler]
      assert is_integer(session_data.expires_at)
      assert session_data.expires_at > DateTime.utc_now() |> DateTime.to_unix()
    end

    test "sets expiration to 24 hours by default" do
      user = %{id: "user_123", email: "test@example.com", roles: [:labeler]}
      session_data = Auth.create_session(user)

      now_unix = DateTime.utc_now() |> DateTime.to_unix()
      expected_expiration = now_unix + 24 * 60 * 60

      # Allow 2 second tolerance for test execution time
      assert_in_delta session_data.expires_at, expected_expiration, 2
    end

    test "accepts custom TTL" do
      user = %{id: "user_123", email: "test@example.com", roles: [:labeler]}
      session_data = Auth.create_session(user, ttl_hours: 2)

      now_unix = DateTime.utc_now() |> DateTime.to_unix()
      expected_expiration = now_unix + 2 * 60 * 60

      assert_in_delta session_data.expires_at, expected_expiration, 2
    end
  end

  describe "validate_session/1" do
    test "validates non-expired session" do
      session_data = %{
        user_id: "user_123",
        user_email: "test@example.com",
        roles: [:labeler],
        expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
      }

      assert {:ok, ^session_data} = Auth.validate_session(session_data)
    end

    test "rejects expired session" do
      session_data = %{
        user_id: "user_123",
        user_email: "test@example.com",
        roles: [:labeler],
        expires_at: DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_unix()
      }

      assert {:error, :expired} = Auth.validate_session(session_data)
    end

    test "rejects session without expiration" do
      session_data = %{
        user_id: "user_123",
        user_email: "test@example.com",
        roles: [:labeler]
      }

      assert {:error, :invalid_session} = Auth.validate_session(session_data)
    end

    test "rejects session without required fields" do
      assert {:error, :invalid_session} = Auth.validate_session(%{user_id: "user_123"})
      assert {:error, :invalid_session} = Auth.validate_session(%{})
      assert {:error, :invalid_session} = Auth.validate_session(nil)
    end
  end

  describe "has_role?/2" do
    test "returns true when user has exact role" do
      assert Auth.has_role?([:labeler, :admin], :labeler)
      assert Auth.has_role?([:admin], :admin)
    end

    test "returns false when user does not have role" do
      refute Auth.has_role?([:labeler], :admin)
      refute Auth.has_role?([], :labeler)
    end

    test "admin role grants all permissions" do
      assert Auth.has_role?([:admin], :labeler)
      assert Auth.has_role?([:admin], :auditor)
      assert Auth.has_role?([:admin], :adjudicator)
    end
  end
end
