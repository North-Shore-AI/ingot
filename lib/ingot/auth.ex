defmodule Ingot.Auth do
  @moduledoc """
  Authentication and session management for Ingot.

  Provides functions for creating and validating sessions, checking roles,
  and managing user authentication state.

  ## Session Management

  Sessions are stored in Phoenix encrypted cookies and include:
  - User ID
  - Email
  - Roles
  - Expiration timestamp

  ## Role Hierarchy

  The `:admin` role grants all permissions. When checking roles,
  admin users are considered to have all roles.

  ## Examples

      # Create a session
      user = %{id: "user_123", email: "test@example.com", roles: [:labeler]}
      session_data = Auth.create_session(user)

      # Validate a session
      case Auth.validate_session(session_data) do
        {:ok, session} -> # Session is valid
        {:error, :expired} -> # Session has expired
        {:error, :invalid_session} -> # Session is malformed
      end

      # Check roles
      Auth.has_role?([:labeler, :admin], :labeler) #=> true
      Auth.has_role?([:admin], :auditor) #=> true (admin has all roles)
  """

  @type session_data :: %{
          required(:user_id) => String.t(),
          required(:user_email) => String.t(),
          required(:roles) => [atom()],
          required(:expires_at) => integer()
        }

  @type user :: %{
          required(:id) => String.t(),
          required(:email) => String.t(),
          required(:roles) => [atom()]
        }

  @default_ttl_hours 24

  @doc """
  Create session data for a user.

  ## Options

    * `:ttl_hours` - Session time-to-live in hours (default: 24)

  ## Examples

      iex> user = %{id: "user_123", email: "test@example.com", roles: [:labeler]}
      iex> session = Auth.create_session(user)
      iex> session.user_id
      "user_123"
  """
  @spec create_session(user(), keyword()) :: session_data()
  def create_session(user, opts \\ []) do
    ttl_hours = Keyword.get(opts, :ttl_hours, @default_ttl_hours)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(ttl_hours * 3600, :second)
      |> DateTime.to_unix()

    %{
      user_id: user.id,
      user_email: user.email,
      roles: user.roles,
      expires_at: expires_at
    }
  end

  @doc """
  Validate session data.

  Returns `{:ok, session_data}` if the session is valid and not expired.
  Returns `{:error, :expired}` if the session has expired.
  Returns `{:error, :invalid_session}` if the session is malformed.

  ## Examples

      iex> session = %{user_id: "123", user_email: "test@example.com", roles: [:labeler], expires_at: future_timestamp}
      iex> Auth.validate_session(session)
      {:ok, %{user_id: "123", ...}}

      iex> expired_session = %{user_id: "123", expires_at: past_timestamp}
      iex> Auth.validate_session(expired_session)
      {:error, :expired}
  """
  @spec validate_session(map() | nil) ::
          {:ok, session_data()} | {:error, :expired | :invalid_session}
  def validate_session(nil), do: {:error, :invalid_session}

  def validate_session(session_data) do
    with :ok <- validate_session_structure(session_data),
         :ok <- validate_session_expiration(session_data) do
      {:ok, session_data}
    end
  end

  @doc """
  Check if a user has a specific role.

  The `:admin` role grants all permissions, so admin users will return `true`
  for any role check.

  ## Examples

      iex> Auth.has_role?([:labeler], :labeler)
      true

      iex> Auth.has_role?([:labeler], :admin)
      false

      iex> Auth.has_role?([:admin], :labeler)
      true
  """
  @spec has_role?([atom()], atom()) :: boolean()
  def has_role?(roles, required_role) when is_list(roles) do
    # Admin role grants all permissions
    :admin in roles or required_role in roles
  end

  def has_role?(_, _), do: false

  # Private helpers

  defp validate_session_structure(session_data) when is_map(session_data) do
    required_keys = [:user_id, :user_email, :roles, :expires_at]

    if Enum.all?(required_keys, &Map.has_key?(session_data, &1)) do
      :ok
    else
      {:error, :invalid_session}
    end
  end

  defp validate_session_structure(_), do: {:error, :invalid_session}

  defp validate_session_expiration(%{expires_at: expires_at}) when is_integer(expires_at) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()

    if expires_at > now_unix do
      :ok
    else
      {:error, :expired}
    end
  end

  defp validate_session_expiration(_), do: {:error, :invalid_session}
end
