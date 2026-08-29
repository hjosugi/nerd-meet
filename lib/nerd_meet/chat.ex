defmodule NerdMeet.Chat do
  @moduledoc """
  Conversations between matched members.

  The send path is deliberately short: authorise, run stage 1, encrypt, insert,
  enqueue. Everything expensive happens after the message has already been
  delivered, so moderation never shows up as latency.

  Authorisation is checked here rather than in the web layer because "you may
  only message someone who chose you back" is a property of the domain, and a
  property enforced in a controller is a property one new controller away from
  not being enforced at all.
  """

  import Ecto.Query, warn: false

  alias NerdMeet.Chat.Conversation
  alias NerdMeet.Chat.ConversationKey
  alias NerdMeet.Chat.Message
  alias NerdMeet.Moderation
  alias NerdMeet.Repo
  alias NerdMeet.Social
  alias NerdMeet.Social.Match
  alias NerdMeet.Vault
  alias NerdMeet.Workers.ScreenSender

  @max_body_bytes 4_000

  @doc """
  Sends a message from one member to another.

  Fails with `{:error, :not_matched}` before anything else happens, which is
  the rule that makes the rest of the moderation stack a backstop rather than
  the primary defence.
  """
  @spec send_message(binary(), binary(), binary()) ::
          {:ok, Message.t()} | {:error, atom() | {:refused, binary()} | Ecto.Changeset.t()}
  def send_message(sender_id, recipient_id, body) when is_binary(body) do
    with :ok <- validate_body(body),
         :ok <- authorize(sender_id, recipient_id),
         {:ok, conversation, key} <- ensure_conversation(sender_id, recipient_id) do
      case Moderation.screen(body) do
        {:block, reason} ->
          {:error, {:refused, reason}}

        decision ->
          state = if match?({:flag, _reason}, decision), do: "flagged", else: "delivered"

          reason =
            case decision do
              {:flag, r} -> r
              _ -> nil
            end

          insert_message(conversation, key, sender_id, body, state, reason)
      end
    end
  end

  @doc """
  Decrypts a message.

  Returns `:error` once the conversation key has been destroyed, which is what
  deletion looks like from the inside: not a missing row, but ciphertext that
  no longer opens.
  """
  @spec decrypt_message(Message.t()) :: {:ok, binary()} | :error
  def decrypt_message(%Message{} = message) do
    with {:ok, key} <- conversation_key(message.conversation_id) do
      Vault.open(key, %{ciphertext: message.ciphertext, iv: message.iv, tag: message.tag})
    end
  end

  @doc """
  Messages in a conversation, decrypted, oldest first.

  A message whose key is gone is returned with a `nil` body rather than being
  hidden, so a shredded conversation reads as "this was deleted" instead of
  silently shrinking.
  """
  @spec list_messages(binary(), keyword()) :: [Message.t()]
  def list_messages(conversation_id, opts \\ []) do
    key =
      case conversation_key(conversation_id) do
        {:ok, key} -> key
        :error -> nil
      end

    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [asc: m.inserted_at],
      limit: ^Keyword.get(opts, :limit, 200)
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | body: decrypt_with(key, &1)})
  end

  @spec get_conversation(binary()) :: Conversation.t() | nil
  def get_conversation(id), do: Repo.get(Conversation, id)

  @doc "The conversation for a pair, if one has been started."
  @spec conversation_for(binary(), binary()) :: Conversation.t() | nil
  def conversation_for(user_id, other_id) do
    case Social.get_match(user_id, other_id) do
      nil -> nil
      %Match{} = match -> Repo.get_by(Conversation, match_id: match.id)
    end
  end

  @doc """
  Creates the conversation and its data key on first use.

  The key is generated here and wrapped immediately; the unwrapped form never
  leaves this function's caller.
  """
  @spec ensure_conversation(binary(), binary()) ::
          {:ok, Conversation.t(), binary()} | {:error, atom()}
  def ensure_conversation(user_id, other_id) do
    case Social.get_match(user_id, other_id) do
      nil ->
        {:error, :not_matched}

      %Match{} = match ->
        conversation =
          case Repo.get_by(Conversation, match_id: match.id) do
            nil -> Repo.insert!(Conversation.changeset(%Conversation{}, %{match_id: match.id}))
            existing -> existing
          end

        {:ok, conversation, ensure_key(conversation)}
    end
  end

  defp ensure_key(%Conversation{id: id}) do
    case conversation_key(id) do
      {:ok, key} ->
        key

      :error ->
        key = Vault.generate_key()
        %{ciphertext: wrapped, iv: iv, tag: tag} = Vault.wrap(key)

        Repo.insert!(
          ConversationKey.changeset(%ConversationKey{}, %{
            conversation_id: id,
            wrapped_key: wrapped,
            wrap_iv: iv,
            wrap_tag: tag
          })
        )

        key
    end
  end

  defp conversation_key(conversation_id) do
    case Repo.get_by(ConversationKey, conversation_id: conversation_id) do
      nil ->
        :error

      row ->
        Vault.unwrap(%{ciphertext: row.wrapped_key, iv: row.wrap_iv, tag: row.wrap_tag})
    end
  end

  defp insert_message(conversation, key, sender_id, body, state, reason) do
    sealed = Vault.seal(key, body)
    now = DateTime.utc_now()

    result =
      %Message{}
      |> Message.changeset(%{
        conversation_id: conversation.id,
        sender_id: sender_id,
        ciphertext: sealed.ciphertext,
        iv: sealed.iv,
        tag: sealed.tag,
        fingerprint: Vault.fingerprint(body),
        moderation_state: state,
        moderation_reason: reason,
        inserted_at: now
      })
      |> Repo.insert()

    with {:ok, message} <- result do
      Repo.update_all(
        from(c in Conversation, where: c.id == ^conversation.id),
        set: [last_message_at: now, updated_at: now]
      )

      %{user_id: sender_id, message_id: message.id}
      |> ScreenSender.new()
      |> Oban.insert()

      {:ok, %{message | body: body}}
    end
  end

  defp authorize(sender_id, recipient_id) do
    cond do
      Social.blocked_either_way?(sender_id, recipient_id) -> {:error, :blocked}
      not Social.matched?(sender_id, recipient_id) -> {:error, :not_matched}
      Moderation.restricted?(sender_id, "send_limit") -> {:error, :send_limited}
      Moderation.restricted?(sender_id, "suspension") -> {:error, :suspended}
      true -> :ok
    end
  end

  defp validate_body(body) do
    trimmed = String.trim(body)

    cond do
      trimmed == "" -> {:error, :empty_body}
      byte_size(body) > @max_body_bytes -> {:error, :body_too_long}
      true -> :ok
    end
  end

  defp decrypt_with(nil, _message), do: nil

  defp decrypt_with(key, message) do
    case Vault.open(key, %{ciphertext: message.ciphertext, iv: message.iv, tag: message.tag}) do
      {:ok, body} -> body
      :error -> nil
    end
  end
end
