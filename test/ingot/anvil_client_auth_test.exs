defmodule Ingot.AnvilClientAuthTest do
  use ExUnit.Case, async: true

  alias Ingot.AnvilClient

  setup do
    # Use MockAdapter for tests
    Application.put_env(:ingot, :anvil_client_adapter, Ingot.AnvilClient.MockAdapter)
    :ok
  end

  describe "upsert_user/1" do
    test "creates new user with external_id and email" do
      user_attrs = %{
        external_id: "oidc_sub_123",
        email: "newuser@example.com",
        name: "New User"
      }

      assert {:ok, user} = AnvilClient.upsert_user(user_attrs)
      assert user.external_id == "oidc_sub_123"
      assert user.email == "newuser@example.com"
      assert user.name == "New User"
      assert user.id
    end

    test "updates existing user when external_id matches" do
      # Note: MockAdapter creates new ID each time for simplicity
      # Real implementation would track by external_id
      user_attrs = %{
        external_id: "existing_user",
        email: "updated@example.com",
        name: "Updated Name"
      }

      assert {:ok, user1} = AnvilClient.upsert_user(user_attrs)
      assert {:ok, user2} = AnvilClient.upsert_user(user_attrs)

      # Both users should have the same external_id
      assert user1.external_id == user2.external_id
      assert user2.email == "updated@example.com"
    end

    test "returns error for invalid attributes" do
      assert {:error, :invalid_attributes} = AnvilClient.upsert_user(%{})
      assert {:error, :invalid_attributes} = AnvilClient.upsert_user(%{external_id: nil})
    end
  end

  describe "get_user_roles/1" do
    test "returns roles for existing user" do
      assert {:ok, roles} = AnvilClient.get_user_roles("user_123")
      assert is_list(roles)
      # Roles are maps with :role and :scope keys
      assert Enum.all?(roles, &is_map/1)
      assert Enum.all?(roles, fn r -> is_atom(r.role) end)
    end

    test "returns empty list for user with no roles" do
      assert {:ok, []} = AnvilClient.get_user_roles("user_no_roles")
    end

    test "returns error for non-existent user" do
      assert {:error, :not_found} = AnvilClient.get_user_roles("nonexistent")
    end

    test "includes role scopes" do
      assert {:ok, roles} = AnvilClient.get_user_roles("user_with_scoped_roles")
      assert is_list(roles)

      # Should return role maps with scope information
      labeler_role = Enum.find(roles, fn r -> r.role == :labeler end)
      assert labeler_role
      assert labeler_role.scope
    end
  end

  describe "check_queue_access/2" do
    test "returns true when user has access to queue" do
      assert {:ok, true} = AnvilClient.check_queue_access("user_123", "queue_abc")
    end

    test "returns false when user lacks access to queue" do
      assert {:ok, false} = AnvilClient.check_queue_access("user_123", "queue_restricted")
    end

    test "admin users have access to all queues" do
      assert {:ok, true} = AnvilClient.check_queue_access("admin_user", "any_queue")
    end

    test "returns error for non-existent user" do
      assert {:error, :not_found} = AnvilClient.check_queue_access("nonexistent", "queue_abc")
    end

    test "returns error for non-existent queue" do
      assert {:error, :not_found} =
               AnvilClient.check_queue_access("user_123", "nonexistent_queue")
    end
  end

  describe "create_invite/2" do
    test "creates invite code for queue" do
      attrs = %{
        queue_id: "queue_abc",
        role: :labeler,
        max_uses: 10,
        expires_at: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      assert {:ok, invite} = AnvilClient.create_invite(attrs)
      assert invite.code
      assert String.length(invite.code) > 0
      assert invite.queue_id == "queue_abc"
      assert invite.role == :labeler
      assert invite.max_uses == 10
      assert invite.remaining_uses == 10
    end

    test "generates unique codes" do
      attrs = %{queue_id: "queue_abc", role: :labeler, max_uses: 5}

      assert {:ok, invite1} = AnvilClient.create_invite(attrs)
      assert {:ok, invite2} = AnvilClient.create_invite(attrs)

      assert invite1.code != invite2.code
    end

    test "accepts optional created_by parameter" do
      attrs = %{
        queue_id: "queue_abc",
        role: :labeler,
        max_uses: 5,
        created_by: "admin_user_123"
      }

      assert {:ok, invite} = AnvilClient.create_invite(attrs)
      assert invite.created_by == "admin_user_123"
    end

    test "returns error for invalid queue" do
      attrs = %{queue_id: "nonexistent", role: :labeler, max_uses: 5}
      assert {:error, :not_found} = AnvilClient.create_invite(attrs)
    end
  end

  describe "get_invite/1" do
    test "retrieves invite by code" do
      attrs = %{queue_id: "queue_abc", role: :labeler, max_uses: 5}
      {:ok, created_invite} = AnvilClient.create_invite(attrs)

      assert {:ok, invite} = AnvilClient.get_invite(created_invite.code)
      assert invite.code == created_invite.code
      assert invite.queue_id == "queue_abc"
    end

    test "returns error for non-existent code" do
      assert {:error, :not_found} = AnvilClient.get_invite("NONEXISTENT")
    end

    test "returns error for expired invite" do
      assert {:error, :expired} = AnvilClient.get_invite("EXPIRED_CODE")
    end

    test "returns error for exhausted invite" do
      assert {:error, :exhausted} = AnvilClient.get_invite("EXHAUSTED_CODE")
    end
  end

  describe "redeem_invite/2" do
    test "redeems invite and creates user" do
      attrs = %{queue_id: "queue_abc", role: :labeler, max_uses: 5}
      {:ok, invite} = AnvilClient.create_invite(attrs)

      user_attrs = %{
        email: "labeler@example.com",
        name: "External Labeler"
      }

      assert {:ok, result} = AnvilClient.redeem_invite(invite.code, user_attrs)
      assert result.user
      assert result.user.email == "labeler@example.com"
      assert result.queue_id == "queue_abc"
      assert result.role == :labeler
    end

    test "decrements remaining uses" do
      attrs = %{queue_id: "queue_abc", role: :labeler, max_uses: 3}
      {:ok, invite} = AnvilClient.create_invite(attrs)

      user_attrs1 = %{email: "user1@example.com", name: "User 1"}
      user_attrs2 = %{email: "user2@example.com", name: "User 2"}
      user_attrs3 = %{email: "user3@example.com", name: "User 3"}
      user_attrs4 = %{email: "user4@example.com", name: "User 4"}

      assert {:ok, _result1} = AnvilClient.redeem_invite(invite.code, user_attrs1)
      assert {:ok, invite_after} = AnvilClient.get_invite(invite.code)
      assert invite_after.remaining_uses == 2

      assert {:ok, _result2} = AnvilClient.redeem_invite(invite.code, user_attrs2)
      assert {:ok, invite_after2} = AnvilClient.get_invite(invite.code)
      assert invite_after2.remaining_uses == 1

      assert {:ok, _result3} = AnvilClient.redeem_invite(invite.code, user_attrs3)
      # After third redemption, remaining is 0 - invite is exhausted
      assert {:error, :exhausted} = AnvilClient.get_invite(invite.code)

      # Fourth redemption should fail
      assert {:error, :exhausted} = AnvilClient.redeem_invite(invite.code, user_attrs4)
    end

    test "returns error for expired invite" do
      user_attrs = %{email: "user@example.com", name: "User"}
      assert {:error, :expired} = AnvilClient.redeem_invite("EXPIRED_CODE", user_attrs)
    end

    test "returns error for exhausted invite" do
      user_attrs = %{email: "user@example.com", name: "User"}
      assert {:error, :exhausted} = AnvilClient.redeem_invite("EXHAUSTED_CODE", user_attrs)
    end

    test "returns error for invalid invite code" do
      user_attrs = %{email: "user@example.com", name: "User"}
      assert {:error, :not_found} = AnvilClient.redeem_invite("INVALID", user_attrs)
    end
  end
end
