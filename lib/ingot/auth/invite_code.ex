defmodule Ingot.Auth.InviteCode do
  @moduledoc """
  Generate and validate invite codes for external labelers.

  Invite codes are used to grant access to specific queues without
  requiring organizational SSO accounts. Codes are alphanumeric strings
  that exclude ambiguous characters (0, O, I, L) for better readability.

  ## Examples

      # Generate a code
      code = InviteCode.generate()
      #=> "ABCD1234WXYZ"

      # Format for display
      InviteCode.format_for_display(code)
      #=> "ABCD-1234-WXYZ"

      # Normalize user input
      InviteCode.normalize("abcd-1234-wxyz")
      #=> "ABCD1234WXYZ"

      # Validate format
      InviteCode.valid_format?("ABCD1234WXYZ")
      #=> true
  """

  # Exclude ambiguous characters: 0 (zero), O, I, L
  @alphabet "123456789ABCDEFGHJKMNPQRSTUVWXYZ"
  @default_length 12
  @min_length 6
  @max_length 32

  @doc """
  Generate a random invite code.

  ## Options

    * `:length` - Code length (default: 12, min: 6, max: 32)

  ## Examples

      iex> code = InviteCode.generate()
      iex> String.length(code)
      12

      iex> code = InviteCode.generate(length: 8)
      iex> String.length(code)
      8
  """
  @spec generate(keyword()) :: String.t()
  def generate(opts \\ []) do
    length = Keyword.get(opts, :length, @default_length)
    length = max(@min_length, min(length, @max_length))

    alphabet_list = String.graphemes(@alphabet)
    alphabet_size = length(alphabet_list)

    1..length
    |> Enum.map(fn _ ->
      Enum.at(alphabet_list, :rand.uniform(alphabet_size) - 1)
    end)
    |> Enum.join()
  end

  @doc """
  Format code with dashes for display readability.

  Inserts dashes every 4 characters.

  ## Examples

      iex> InviteCode.format_for_display("ABCD1234WXYZ")
      "ABCD-1234-WXYZ"

      iex> InviteCode.format_for_display("ABC123")
      "ABC1-23"
  """
  @spec format_for_display(String.t()) :: String.t()
  def format_for_display(code) when is_binary(code) do
    code
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map(&Enum.join/1)
    |> Enum.join("-")
  end

  def format_for_display(_), do: ""

  @doc """
  Normalize user input by removing dashes/spaces and uppercasing.

  ## Examples

      iex> InviteCode.normalize("abcd-1234-wxyz")
      "ABCD1234WXYZ"

      iex> InviteCode.normalize("ABCD 1234 WXYZ")
      "ABCD1234WXYZ"

      iex> InviteCode.normalize(nil)
      ""
  """
  @spec normalize(String.t() | nil) :: String.t()
  def normalize(nil), do: ""
  def normalize(""), do: ""

  def normalize(code) when is_binary(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[\s\-_]/, "")
  end

  @doc """
  Validate invite code format.

  Checks that the code:
  - Is not empty
  - Contains only valid characters (no ambiguous chars)
  - Is within acceptable length range

  ## Examples

      iex> InviteCode.valid_format?("ABCD1234WXYZ")
      true

      iex> InviteCode.valid_format?("ABCD-1234")
      false

      iex> InviteCode.valid_format?("ABCD0123")
      false
  """
  @spec valid_format?(String.t() | nil) :: boolean()
  def valid_format?(nil), do: false
  def valid_format?(""), do: false

  def valid_format?(code) when is_binary(code) do
    # Check length
    length_ok? = String.length(code) >= @min_length and String.length(code) <= @max_length

    # Check all characters are in alphabet
    alphabet_chars = String.graphemes(@alphabet)
    all_valid_chars? = code |> String.graphemes() |> Enum.all?(&(&1 in alphabet_chars))

    length_ok? and all_valid_chars?
  end

  def valid_format?(_), do: false
end
