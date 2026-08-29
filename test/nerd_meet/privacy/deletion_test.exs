defmodule NerdMeet.Privacy.DeletionTest do
  use NerdMeet.DataCase, async: true

  alias NerdMeet.Accounts.User
  alias NerdMeet.Chat
  alias NerdMeet.Fixtures
  alias NerdMeet.Privacy.Deletion

  describe "crypto-shredding" do
    test "destroying the key makes stored messages unreadable" do
      {a, b} = Fixtures.matched_pair()
      {:ok, message} = Chat.send_message(a.id, b.id, "この会話は消える")
      conversation_id = message.conversation_id

      assert {:ok, "この会話は消える"} = Chat.decrypt_message(reload(message))

      Deletion.shred_conversation(conversation_id)

      assert Deletion.shredded?(conversation_id)
      assert :error = Chat.decrypt_message(reload(message))
    end

    test "the ciphertext is still there, and still useless" do
      {a, b} = Fixtures.matched_pair()
      {:ok, message} = Chat.send_message(a.id, b.id, "残るのは暗号文だけ")

      Deletion.shred_conversation(message.conversation_id)
      stored = reload(message)

      # The row survives, which is the honest outcome: backups exist. What does
      # not survive is anything able to open it.
      assert stored.ciphertext
      assert :error = Chat.decrypt_message(stored)
    end

    test "a shredded conversation lists messages with no body rather than hiding them" do
      {a, b} = Fixtures.matched_pair()
      {:ok, message} = Chat.send_message(a.id, b.id, "履歴は残る")

      Deletion.shred_conversation(message.conversation_id)
      [listed] = Chat.list_messages(message.conversation_id)

      assert listed.body == nil
    end
  end

  describe "delete_account/2" do
    test "shreds every conversation the member was part of" do
      {a, b} = Fixtures.matched_pair()
      {:ok, message} = Chat.send_message(a.id, b.id, "退会します")

      assert {:ok, %{shredded: 1}} = Deletion.delete_account(a.id)
      assert Deletion.shredded?(message.conversation_id)
    end

    test "removes the profile and marks the account deleted" do
      {a, b} = Fixtures.matched_pair()
      {:ok, _message} = Chat.send_message(a.id, b.id, "退会します")

      {:ok, _result} = Deletion.delete_account(a.id)
      user = Repo.get!(User, a.id)

      assert user.status == "deleted"
      assert user.deleted_at
      assert is_nil(NerdMeet.Members.get_profile(a.id))
    end

    test "voluntary deletion lets the person come back, suspension does not" do
      voluntary = Fixtures.member()
      banned = Fixtures.member()

      {:ok, _first} = Deletion.delete_account(voluntary.id)
      {:ok, _second} = Deletion.delete_account(banned.id, keep_identity_hash: true)

      assert is_nil(Repo.get!(User, voluntary.id).identity_serial_hash)
      assert Repo.get!(User, banned.id).identity_serial_hash
    end

    test "writes an audit row saying what was destroyed" do
      {a, b} = Fixtures.matched_pair()
      {:ok, _message} = Chat.send_message(a.id, b.id, "記録は残す")

      {:ok, _result} = Deletion.delete_account(a.id)
      [entry] = NerdMeet.Moderation.audit_trail("user", a.id)

      assert entry.action == "account.delete"
      assert entry.metadata["conversations_shredded"] == 1
    end
  end

  defp reload(message), do: Repo.get!(NerdMeet.Chat.Message, message.id)
end
