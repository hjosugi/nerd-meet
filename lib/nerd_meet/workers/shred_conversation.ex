defmodule NerdMeet.Workers.ShredConversation do
  @moduledoc """
  Destroys a conversation key.

  A job rather than an inline call so that deletion survives the request that
  asked for it: a member who closes the tab has still deleted their data.
  """
  use Oban.Worker, queue: :deletion, max_attempts: 5

  alias NerdMeet.Privacy.Deletion

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"conversation_id" => conversation_id}}) do
    Deletion.shred_conversation(conversation_id)
    :ok
  end
end
