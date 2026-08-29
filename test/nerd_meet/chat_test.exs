defmodule NerdMeet.ChatTest do
  use NerdMeet.DataCase, async: true

  alias NerdMeet.Chat
  alias NerdMeet.Chat.Message
  alias NerdMeet.Fixtures
  alias NerdMeet.Social

  describe "who may send" do
    test "a stranger cannot send anything" do
      a = Fixtures.member()
      b = Fixtures.member()

      assert {:error, :not_matched} = Chat.send_message(a.id, b.id, "はじめまして")
    end

    test "a one-way like still cannot send" do
      a = Fixtures.member()
      b = Fixtures.member()
      {:ok, _like} = Social.like(a.id, b.id)

      assert {:error, :not_matched} = Chat.send_message(a.id, b.id, "はじめまして")
    end

    test "a mutual like opens the conversation" do
      {a, b} = Fixtures.matched_pair()

      assert {:ok, message} = Chat.send_message(a.id, b.id, "はじめまして、Elixir書いてます")
      assert message.moderation_state == "delivered"
    end

    test "a block closes it again" do
      {a, b} = Fixtures.matched_pair()
      {:ok, _first} = Chat.send_message(a.id, b.id, "こんにちは")
      {:ok, _block} = Social.block(b.id, a.id, "not interested")

      assert {:error, :blocked} = Chat.send_message(a.id, b.id, "もう一度")
    end
  end

  describe "storage" do
    test "the stored row contains no plaintext" do
      {a, b} = Fixtures.matched_pair()
      secret = "PostgreSQLのVACUUMの話がしたい"

      {:ok, message} = Chat.send_message(a.id, b.id, secret)
      stored = Repo.get!(Message, message.id)

      refute stored.ciphertext == secret
      refute String.contains?(stored.ciphertext, "VACUUM")
      refute String.contains?(stored.ciphertext, "PostgreSQL")
      assert byte_size(stored.iv) == 12
      assert byte_size(stored.tag) == 16
    end

    test "reading it back returns the original text" do
      {a, b} = Fixtures.matched_pair()
      {:ok, message} = Chat.send_message(a.id, b.id, "インデックス設計の話をしましょう")

      assert {:ok, "インデックス設計の話をしましょう"} =
               Chat.decrypt_message(Repo.get!(Message, message.id))
    end

    test "list_messages decrypts in order" do
      {a, b} = Fixtures.matched_pair()
      {:ok, first} = Chat.send_message(a.id, b.id, "ひとつめ")
      {:ok, _second} = Chat.send_message(b.id, a.id, "ふたつめ")

      bodies =
        first.conversation_id
        |> Chat.list_messages()
        |> Enum.map(& &1.body)

      assert bodies == ["ひとつめ", "ふたつめ"]
    end
  end

  describe "stage 1 on the send path" do
    test "a solicitation is refused before it is stored" do
      {a, b} = Fixtures.matched_pair()

      assert {:error, {:refused, "solicitation"}} = Chat.send_message(a.id, b.id, "ホ別2で")
      assert a.id |> Chat.conversation_for(b.id) |> is_nil() or messages_count(a, b) == 0
    end

    test "a contact exchange is refused with a reason the sender can read" do
      {a, b} = Fixtures.matched_pair()

      assert {:error, {:refused, reason}} = Chat.send_message(a.id, b.id, "LINE の ID は abc_123")
      assert reason == "external_contact"
      assert NerdMeet.Moderation.explain(reason) =~ "外部の連絡先"
    end

    test "a link is flagged but still delivered" do
      {a, b} = Fixtures.matched_pair()

      assert {:ok, message} = Chat.send_message(a.id, b.id, "https://example.com/blog 書きました")
      assert message.moderation_state == "flagged"
      assert message.moderation_reason == "external_url"
    end

    test "an empty message is rejected" do
      {a, b} = Fixtures.matched_pair()

      assert {:error, :empty_body} = Chat.send_message(a.id, b.id, "   ")
    end
  end

  defp messages_count(a, b) do
    case Chat.conversation_for(a.id, b.id) do
      nil -> 0
      conversation -> conversation.id |> Chat.list_messages() |> length()
    end
  end
end
