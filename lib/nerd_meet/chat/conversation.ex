defmodule NerdMeet.Chat.Conversation do
  @moduledoc "The thread attached to a match. Created lazily on first message."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversations" do
    field :last_message_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    belongs_to :match, NerdMeet.Social.Match
    has_one :key, NerdMeet.Chat.ConversationKey
    has_many :messages, NerdMeet.Chat.Message

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:match_id, :last_message_at, :closed_at])
    |> validate_required([:match_id])
    |> unique_constraint(:match_id)
  end
end
