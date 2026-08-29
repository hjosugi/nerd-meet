defmodule NerdMeet.Chat.Message do
  @moduledoc """
  A message, stored only as ciphertext.

  `moderation_state` records what stage 1 decided at send time. A flagged
  message is still delivered; the flag is a head start for the background
  stages, not a punishment.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @states ~w(delivered flagged withheld)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "messages" do
    field :ciphertext, :binary
    field :iv, :binary
    field :tag, :binary
    field :fingerprint, :binary
    field :moderation_state, :string, default: "delivered"
    field :moderation_reason, :string
    field :inserted_at, :utc_datetime_usec

    # Populated on read, never persisted.
    field :body, :string, virtual: true

    belongs_to :conversation, NerdMeet.Chat.Conversation
    belongs_to :sender, NerdMeet.Accounts.User
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :conversation_id,
      :sender_id,
      :ciphertext,
      :iv,
      :tag,
      :fingerprint,
      :moderation_state,
      :moderation_reason,
      :inserted_at
    ])
    |> validate_required([:conversation_id, :sender_id, :ciphertext, :iv, :tag])
    |> validate_inclusion(:moderation_state, @states)
  end

  def states, do: @states
end
