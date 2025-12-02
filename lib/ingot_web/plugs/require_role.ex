defmodule IngotWeb.Plugs.RequireRole do
  @moduledoc """
  Plug to require specific role for routes.

  Checks that the current user has the required role.
  Must be used after RequireAuth plug.

  ## Usage

      # In router
      pipeline :admin_required do
        plug IngotWeb.Plugs.RequireAuth
        plug IngotWeb.Plugs.RequireRole, role: :admin
      end

      # With custom redirect
      pipeline :labeler_required do
        plug IngotWeb.Plugs.RequireAuth
        plug IngotWeb.Plugs.RequireRole, role: :labeler, redirect_to: "/dashboard"
      end

  ## Role Hierarchy

  The `:admin` role grants all permissions. Users with admin role
  will pass all role checks regardless of the required role.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  alias Ingot.Auth

  @type options :: keyword()

  @doc false
  @spec init(options()) :: options()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), options()) :: Plug.Conn.t()
  def call(conn, opts) do
    required_role = Keyword.fetch!(opts, :role)
    redirect_path = Keyword.get(opts, :redirect_to, "/")

    current_user = conn.assigns[:current_user]

    cond do
      # No current_user assigned - should have been set by RequireAuth
      is_nil(current_user) ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: redirect_path)
        |> halt()

      # Check if user has required role
      Auth.has_role?(current_user.roles, required_role) ->
        conn

      # User lacks required role
      true ->
        conn
        |> put_flash(:error, "You do not have permission to access this page.")
        |> redirect(to: redirect_path)
        |> halt()
    end
  end
end
