defmodule NerdMeet.Chat.ConversationKey do
  @moduledoc """
  The wrapped data key for one conversation.

  This row is the only thing standing between stored ciphertext and plaintext.
  Deleting it is deletion: not a flag, not a soft delete, not a promise.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversation_keys" do
    field :wrapped_key, :binary
    field :wrap_iv, :binary
    field :wrap_tag, :binary
    field :inserted_at, :utc_datetime_usec

    belongs_to :conversation, NerdMeet.Chat.Conversation
  end

  @doc false
  def changeset(key, attrs) do
    key
    |> cast(attrs, [:conversation_id, :wrapped_key, :wrap_iv, :wrap_tag])
    |> validate_required([:conversation_id, :wrapped_key, :wrap_iv, :wrap_tag])
    |> put_change(:inserted_at, DateTime.utc_now())
    |> unique_constraint(:conversation_id)
  end
end
