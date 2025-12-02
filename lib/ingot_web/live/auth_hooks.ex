defmodule IngotWeb.Live.AuthHooks do
  @moduledoc """
  LiveView on_mount hooks for authentication and authorization.

  Provides hooks that can be used in LiveView modules to require
  authentication and check permissions.

  ## Usage

      defmodule MyAppWeb.SomeLive do
        use MyAppWeb, :live_view

        # Require authentication
        on_mount {IngotWeb.Live.AuthHooks, :require_authenticated_user}

        # Require specific role
        on_mount {IngotWeb.Live.AuthHooks, {:require_role, :admin}}

        # Check queue access
        on_mount {IngotWeb.Live.AuthHooks, {:require_queue_access, "queue_id"}}
      end

  ## Assigns

  The following assigns are set by these hooks:

    * `:current_user` - Map containing user_id, email, and roles (set by :require_authenticated_user)
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Ingot.Auth
  alias Ingot.AnvilClient

  @doc """
  on_mount hook for authentication and authorization.

  Supports multiple hooks:
  - `:require_authenticated_user` - Validates session and assigns current_user
  - `{:require_role, role}` - Checks that user has specific role
  - `{:require_queue_access, queue_id}` - Verifies user has access to queue
  """
  def on_mount(:require_authenticated_user, _params, session, socket) do
    session_data = %{
      user_id: Map.get(session, "user_id"),
      user_email: Map.get(session, "user_email"),
      roles: Map.get(session, "roles", []),
      expires_at: Map.get(session, "expires_at")
    }

    case Auth.validate_session(session_data) do
      {:ok, validated_session} ->
        current_user = %{
          id: validated_session.user_id,
          email: validated_session.user_email,
          roles: validated_session.roles
        }

        socket =
          socket
          |> assign(:current_user, current_user)
          |> assign(:user_id, current_user.id)

        {:cont, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, "You must be logged in to access this page.")
          |> redirect(to: "/")

        {:halt, socket}
    end
  end

  def on_mount({:require_role, required_role}, _params, _session, socket) do
    current_user = socket.assigns[:current_user]

    cond do
      is_nil(current_user) ->
        socket =
          socket
          |> put_flash(:error, "You must be logged in to access this page.")
          |> redirect(to: "/")

        {:halt, socket}

      Auth.has_role?(current_user.roles, required_role) ->
        {:cont, socket}

      true ->
        socket =
          socket
          |> put_flash(:error, "You do not have permission to access this page.")
          |> redirect(to: "/")

        {:halt, socket}
    end
  end

  def on_mount({:require_queue_access, queue_id_or_param}, params, _session, socket)
      when is_binary(queue_id_or_param) do
    current_user = socket.assigns[:current_user]

    if is_nil(current_user) do
      socket =
        socket
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/")

      {:halt, socket}
    else
      # Extract queue_id from params if it's a parameter name
      queue_id =
        if String.starts_with?(queue_id_or_param, ":") do
          param_name = String.trim_leading(queue_id_or_param, ":")
          Map.get(params, param_name)
        else
          queue_id_or_param
        end

      case AnvilClient.check_queue_access(current_user.id, queue_id) do
        {:ok, true} ->
          {:cont, assign(socket, :queue_id, queue_id)}

        {:ok, false} ->
          socket =
            socket
            |> put_flash(:error, "You do not have access to this queue.")
            |> redirect(to: "/")

          {:halt, socket}

        {:error, _reason} ->
          socket =
            socket
            |> put_flash(:error, "Unable to verify queue access.")
            |> redirect(to: "/")

          {:halt, socket}
      end
    end
  end

  def on_mount(unknown_hook, _params, _session, _socket) do
    raise ArgumentError, """
    Unknown auth hook: #{inspect(unknown_hook)}

    Available hooks:
      - :require_authenticated_user
      - {:require_role, role}
      - {:require_queue_access, queue_id}
    """
  end
end
