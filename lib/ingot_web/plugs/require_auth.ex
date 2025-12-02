defmodule IngotWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug to require authentication for routes.

  Validates the session and assigns current_user to conn.
  Redirects to login page if authentication fails.

  ## Usage

      # In router
      pipeline :authenticated do
        plug IngotWeb.Plugs.RequireAuth
      end

      # With custom redirect
      pipeline :authenticated do
        plug IngotWeb.Plugs.RequireAuth, redirect_to: "/login"
      end

  ## Assigns

  On successful authentication, assigns the following to conn:

    * `:current_user` - Map containing user_id, email, and roles
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
    redirect_path = Keyword.get(opts, :redirect_to, "/")

    session_data = %{
      user_id: get_session(conn, :user_id),
      user_email: get_session(conn, :user_email),
      roles: get_session(conn, :roles),
      expires_at: get_session(conn, :expires_at)
    }

    case Auth.validate_session(session_data) do
      {:ok, session} ->
        current_user = %{
          id: session.user_id,
          email: session.user_email,
          roles: session.roles
        }

        assign(conn, :current_user, current_user)

      {:error, :expired} ->
        conn
        |> clear_session()
        |> put_flash(:error, "Your session has expired. Please log in again.")
        |> redirect(to: redirect_path)
        |> halt()

      {:error, :invalid_session} ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: redirect_path)
        |> halt()
    end
  end
end
