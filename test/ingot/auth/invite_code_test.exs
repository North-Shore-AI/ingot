defmodule Ingot.Auth.InviteCodeTest do
  use ExUnit.Case, async: true

  alias Ingot.Auth.InviteCode

  describe "generate/1" do
    test "generates invite code with default length" do
      code = InviteCode.generate()

      assert is_binary(code)
      assert String.length(code) == 12
      assert String.match?(code, ~r/^[A-Z0-9]+$/)
    end

    test "generates invite code with custom length" do
      code = InviteCode.generate(length: 20)

      assert String.length(code) == 20
      assert String.match?(code, ~r/^[A-Z0-9]+$/)
    end

    test "generates unique codes" do
      code1 = InviteCode.generate()
      code2 = InviteCode.generate()

      assert code1 != code2
    end

    test "excludes ambiguous characters" do
      # Generate many codes to increase chances of seeing all character types
      codes = for _ <- 1..100, do: InviteCode.generate()

      all_chars =
        codes
        |> Enum.join()
        |> String.graphemes()
        |> Enum.uniq()

      # Should not contain 0, O, I, L (ambiguous characters)
      refute "0" in all_chars
      refute "O" in all_chars
      refute "I" in all_chars
      refute "L" in all_chars
    end
  end

  describe "format_for_display/1" do
    test "formats code with dashes for readability" do
      code = "ABCD1234WXYZ"
      formatted = InviteCode.format_for_display(code)

      assert formatted == "ABCD-1234-WXYZ"
    end

    test "handles codes of different lengths" do
      assert InviteCode.format_for_display("ABC123") == "ABC1-23"
      assert InviteCode.format_for_display("ABCD1234") == "ABCD-1234"
      assert InviteCode.format_for_display("AB") == "AB"
    end

    test "preserves original code if no formatting needed" do
      assert InviteCode.format_for_display("ABC") == "ABC"
    end
  end

  describe "normalize/1" do
    test "removes dashes and whitespace" do
      assert InviteCode.normalize("ABCD-1234-WXYZ") == "ABCD1234WXYZ"
      assert InviteCode.normalize("ABCD 1234 WXYZ") == "ABCD1234WXYZ"
      assert InviteCode.normalize("ABCD-1234 WXYZ") == "ABCD1234WXYZ"
    end

    test "converts to uppercase" do
      assert InviteCode.normalize("abcd1234wxyz") == "ABCD1234WXYZ"
      assert InviteCode.normalize("AbCd-1234-WxYz") == "ABCD1234WXYZ"
    end

    test "handles empty and nil values" do
      assert InviteCode.normalize("") == ""
      assert InviteCode.normalize(nil) == ""
    end
  end

  describe "valid_format?/1" do
    test "validates correctly formatted codes" do
      assert InviteCode.valid_format?("ABCD1234WXYZ")
      assert InviteCode.valid_format?("ABC123")
      assert InviteCode.valid_format?("A1B2C3D4")
    end

    test "rejects codes with invalid characters" do
      refute InviteCode.valid_format?("ABCD-1234")
      refute InviteCode.valid_format?("ABCD 1234")
      refute InviteCode.valid_format?("abcd1234")
      refute InviteCode.valid_format?("ABCD_1234")
    end

    test "rejects codes with ambiguous characters" do
      refute InviteCode.valid_format?("ABCD0123")
      refute InviteCode.valid_format?("ABCDO123")
      refute InviteCode.valid_format?("ABCDI123")
      refute InviteCode.valid_format?("ABCDL123")
    end

    test "rejects empty or nil codes" do
      refute InviteCode.valid_format?("")
      refute InviteCode.valid_format?(nil)
    end

    test "rejects codes that are too short or too long" do
      refute InviteCode.valid_format?("AB")
      refute InviteCode.valid_format?("A" <> String.duplicate("1", 50))
    end
  end
end
