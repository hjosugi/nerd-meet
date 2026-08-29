defmodule NerdMeet.Privacy.Deletion do
  @moduledoc """
  Deletion that is structural rather than promised.

  Most services implement "delete my data" as a `DELETE` statement whose effect
  nobody outside the operator can verify, and which backups quietly undo. Here
  the messages are encrypted under a per-conversation key, and deletion
  destroys the key. The ciphertext may survive in a backup for as long as the
  retention policy says; it opens for nobody, including us, including a court
  order, because the material required no longer exists.

  One deliberate asymmetry: voluntary deletion clears the identity hash so the
  person can come back, while suspension keeps it so that a banned operator
  cannot simply re-verify with the same card. Both are deletions of personal
  data; only one is also an enforcement action.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias NerdMeet.Accounts.Credential
  alias NerdMeet.Accounts.User
  alias NerdMeet.Chat.Conversation
  alias NerdMeet.Chat.ConversationKey
  alias NerdMeet.Members.Profile
  alias NerdMeet.Members.SavedQuery
  alias NerdMeet.Moderation
  alias NerdMeet.Repo
  alias NerdMeet.Social.Like

  @doc """
  Destroys the key for one conversation. The messages stay, unreadable.
  """
  @spec shred_conversation(binary()) :: {non_neg_integer(), nil}
  def shred_conversation(conversation_id) do
    Repo.delete_all(from k in ConversationKey, where: k.conversation_id == ^conversation_id)
  end

  @doc """
  Deletes an account.

  Returns the number of conversations shredded, which is the number worth
  reporting back to the person: it is the part that cannot be undone.
  """
  @spec delete_account(binary(), keyword()) ::
          {:ok, %{shredded: non_neg_integer()}} | {:error, term()}
  def delete_account(user_id, opts \\ []) do
    keep_identity_hash = Keyword.get(opts, :keep_identity_hash, false)
    reason = Keyword.get(opts, :reason, "member requested deletion")

    conversation_ids = conversation_ids_for(user_id)

    Multi.new()
    |> Multi.delete_all(
      :keys,
      from(k in ConversationKey, where: k.conversation_id in ^conversation_ids)
    )
    |> Multi.delete_all(:profile, from(p in Profile, where: p.user_id == ^user_id))
    |> Multi.delete_all(:queries, from(q in SavedQuery, where: q.user_id == ^user_id))
    |> Multi.delete_all(
      :likes,
      from(l in Like, where: l.from_user_id == ^user_id or l.to_user_id == ^user_id)
    )
    |> Multi.delete_all(:credentials, from(c in Credential, where: c.user_id == ^user_id))
    |> Multi.update_all(
      :user,
      from(u in User, where: u.id == ^user_id),
      set: user_updates(keep_identity_hash)
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        Moderation.audit(nil, "account.delete", "user", user_id, reason, %{
          "conversations_shredded" => length(conversation_ids),
          "identity_hash_retained" => keep_identity_hash
        })

        {:ok, %{shredded: length(conversation_ids)}}

      {:error, step, reason, _changes} ->
        {:error, {step, reason}}
    end
  end

  @doc """
  True once a conversation can no longer be read by anyone.

  Exists so that "deleted" is an assertion a test can make, not a claim in a
  privacy policy.
  """
  @spec shredded?(binary()) :: boolean()
  def shredded?(conversation_id) do
    not Repo.exists?(from k in ConversationKey, where: k.conversation_id == ^conversation_id)
  end

  defp conversation_ids_for(user_id) do
    Repo.all(
      from c in Conversation,
        join: m in assoc(c, :match),
        where: m.user_a_id == ^user_id or m.user_b_id == ^user_id,
        select: c.id
    )
  end

  defp user_updates(true) do
    now = DateTime.utc_now()

    [
      status: "deleted",
      deleted_at: now,
      updated_at: now,
      last_country: nil,
      last_latitude: nil,
      last_longitude: nil
    ]
  end

  defp user_updates(false) do
    Keyword.put(user_updates(true), :identity_serial_hash, nil)
  end
end
