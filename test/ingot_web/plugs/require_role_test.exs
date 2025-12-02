defmodule IngotWeb.Plugs.RequireRoleTest do
  use IngotWeb.ConnCase, async: true

  alias IngotWeb.Plugs.RequireRole

  describe "init/1" do
    test "extracts required role from options" do
      assert RequireRole.init(role: :admin) == [role: :admin]
      assert RequireRole.init(role: :labeler) == [role: :labeler]
    end
  end

  describe "call/2" do
    test "allows request when user has required role" do
      conn =
        build_conn()
        |> assign(:current_user, %{
          id: "user_123",
          email: "test@example.com",
          roles: [:labeler, :auditor]
        })
        |> RequireRole.call(role: :labeler)

      refute conn.halted
    end

    test "allows request when user is admin" do
      conn =
        build_conn()
        |> assign(:current_user, %{
          id: "user_123",
          email: "admin@example.com",
          roles: [:admin]
        })
        |> RequireRole.call(role: :labeler)

      refute conn.halted
    end

    test "blocks request when user lacks required role" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> assign(:current_user, %{
          id: "user_123",
          email: "test@example.com",
          roles: [:labeler]
        })
        |> RequireRole.call(role: :admin)

      assert conn.halted
      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You do not have permission to access this page."
    end

    test "blocks request when user has no roles" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> assign(:current_user, %{
          id: "user_123",
          email: "test@example.com",
          roles: []
        })
        |> RequireRole.call(role: :labeler)

      assert conn.halted
    end

    test "blocks request when current_user is not assigned" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> RequireRole.call(role: :labeler)

      assert conn.halted
      assert redirected_to(conn) == "/"
    end

    test "redirects to custom path when provided" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()
        |> assign(:current_user, %{
          id: "user_123",
          roles: [:labeler]
        })
        |> RequireRole.call(role: :admin, redirect_to: "/dashboard")

      assert conn.halted
      assert redirected_to(conn) == "/dashboard"
    end
  end
end
