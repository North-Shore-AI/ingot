defmodule IngotWeb.Plugs.RequireAuthTest do
  use IngotWeb.ConnCase, async: true

  alias IngotWeb.Plugs.RequireAuth

  describe "init/1" do
    test "returns options unchanged" do
      assert RequireAuth.init([]) == []
      assert RequireAuth.init(redirect_to: "/login") == [redirect_to: "/login"]
    end
  end

  describe "call/2" do
    test "allows request with valid session" do
      conn =
        build_conn()
        |> init_test_session(%{
          user_id: "user_123",
          user_email: "test@example.com",
          roles: [:labeler],
          expires_at: future_timestamp()
        })
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> RequireAuth.call([])

      refute conn.halted
      assert conn.assigns.current_user
      assert conn.assigns.current_user.id == "user_123"
      assert conn.assigns.current_user.email == "test@example.com"
      assert conn.assigns.current_user.roles == [:labeler]
    end

    test "redirects when session is missing" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> RequireAuth.call([])

      assert conn.halted
      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must be logged in to access this page."
    end

    test "redirects when session is expired" do
      conn =
        build_conn()
        |> init_test_session(%{
          user_id: "user_123",
          user_email: "test@example.com",
          roles: [:labeler],
          expires_at: past_timestamp()
        })
        |> Phoenix.Controller.fetch_flash()
        |> RequireAuth.call([])

      assert conn.halted
      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your session has expired. Please log in again."
    end

    test "redirects to custom path when provided" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> RequireAuth.call(redirect_to: "/custom/login")

      assert conn.halted
      assert redirected_to(conn) == "/custom/login"
    end

    test "clears expired session" do
      conn =
        build_conn()
        |> init_test_session(%{
          user_id: "user_123",
          expires_at: past_timestamp()
        })
        |> Phoenix.Controller.fetch_flash()
        |> RequireAuth.call([])

      assert get_session(conn, :user_id) == nil
    end
  end

  defp future_timestamp do
    DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
  end

  defp past_timestamp do
    DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_unix()
  end
end
