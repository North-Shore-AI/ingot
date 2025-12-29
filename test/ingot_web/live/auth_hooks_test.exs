defmodule IngotWeb.Live.AuthHooksTest do
  use IngotWeb.ConnCase, async: true

  alias IngotWeb.Live.AuthHooks

  defp build_socket do
    %Phoenix.LiveView.Socket{
      endpoint: IngotWeb.Endpoint,
      router: IngotWeb.Router,
      assigns: %{__changed__: %{}, flash: %{}}
    }
  end

  defp build_socket_with_user(user) do
    %Phoenix.LiveView.Socket{
      endpoint: IngotWeb.Endpoint,
      router: IngotWeb.Router,
      assigns: %{__changed__: %{}, flash: %{}, current_user: user}
    }
  end

  describe "on_mount :require_authenticated_user" do
    test "allows access with valid session" do
      session = %{
        "user_id" => "user_123",
        "user_email" => "test@example.com",
        "roles" => [:labeler],
        "expires_at" => future_timestamp()
      }

      socket = build_socket()
      {:cont, socket} = AuthHooks.on_mount(:require_authenticated_user, %{}, session, socket)

      assert socket.assigns.current_user
      assert socket.assigns.current_user.id == "user_123"
      assert socket.assigns.current_user.email == "test@example.com"
      assert socket.assigns.current_user.roles == [:labeler]
      assert socket.assigns.user_id == "user_123"
    end

    test "redirects when session is missing" do
      socket = build_socket()
      {:halt, socket} = AuthHooks.on_mount(:require_authenticated_user, %{}, %{}, socket)

      assert socket.redirected
    end

    test "redirects when session is expired" do
      session = %{
        "user_id" => "user_123",
        "user_email" => "test@example.com",
        "roles" => [:labeler],
        "expires_at" => past_timestamp()
      }

      socket = build_socket()
      {:halt, socket} = AuthHooks.on_mount(:require_authenticated_user, %{}, session, socket)

      assert socket.redirected
    end
  end

  describe "on_mount {:require_role, role}" do
    test "allows access when user has required role" do
      user = %{
        id: "user_123",
        email: "test@example.com",
        roles: [:labeler, :auditor]
      }

      socket = build_socket_with_user(user)
      {:cont, _socket} = AuthHooks.on_mount({:require_role, :labeler}, %{}, %{}, socket)
    end

    test "allows access when user is admin" do
      user = %{
        id: "admin_123",
        email: "admin@example.com",
        roles: [:admin]
      }

      socket = build_socket_with_user(user)
      {:cont, _socket} = AuthHooks.on_mount({:require_role, :auditor}, %{}, %{}, socket)
    end

    test "blocks access when user lacks required role" do
      user = %{
        id: "user_123",
        email: "test@example.com",
        roles: [:labeler]
      }

      socket = build_socket_with_user(user)
      {:halt, socket} = AuthHooks.on_mount({:require_role, :admin}, %{}, %{}, socket)

      assert socket.redirected
    end

    test "blocks access when current_user is not assigned" do
      socket = build_socket()
      {:halt, socket} = AuthHooks.on_mount({:require_role, :labeler}, %{}, %{}, socket)

      assert socket.redirected
    end
  end

  defp future_timestamp do
    DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
  end

  defp past_timestamp do
    DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_unix()
  end
end
