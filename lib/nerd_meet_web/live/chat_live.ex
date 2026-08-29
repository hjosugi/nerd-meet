defmodule NerdMeetWeb.ChatLive do
  @moduledoc """
  One conversation.

  Refusals from stage 1 are shown to the sender with the rule they hit. That is
  a deliberate choice: a member who did not know the rule now does, and an
  operator learns nothing they would not have learned from one more attempt.
  """
  use NerdMeetWeb, :live_view

  alias NerdMeet.Chat
  alias NerdMeet.Members
  alias NerdMeet.Moderation
  alias NerdMeet.Social

  @impl true
  def mount(%{"user_id" => other_id}, _session, socket) do
    user = socket.assigns.current_user

    cond do
      is_nil(user) ->
        {:ok, redirect(socket, to: ~p"/")}

      not Social.matched?(user.id, other_id) ->
        {:ok,
         socket
         |> put_flash(:error, "この相手とはまだマッチしていません")
         |> redirect(to: ~p"/matches")}

      true ->
        profile = Members.get_profile(other_id)

        {:ok,
         socket
         |> assign(
           other_id: other_id,
           other_name: (profile && profile.display_name) || "相手",
           draft: "",
           refusal: nil,
           page_title: "会話"
         )
         |> assign(:messages, load_messages(user.id, other_id))}
    end
  end

  @impl true
  def handle_event("send", %{"body" => body}, socket) do
    user = socket.assigns.current_user

    case Chat.send_message(user.id, socket.assigns.other_id, body) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(draft: "", refusal: nil)
         |> assign(:messages, load_messages(user.id, socket.assigns.other_id))}

      {:error, {:refused, reason}} ->
        {:noreply, assign(socket, draft: body, refusal: Moderation.explain(reason))}

      {:error, :empty_body} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, refusal: humanize(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex h-[calc(100vh-6rem)] max-w-3xl flex-col px-4 py-6">
      <header class="border-b border-zinc-200 pb-3">
        <.link navigate={~p"/matches"} class="text-sm text-zinc-500">← マッチ一覧</.link>
        <h1 class="mt-1 text-xl font-semibold text-zinc-900">{@other_name}</h1>
      </header>

      <div class="flex-1 space-y-3 overflow-y-auto py-4">
        <div :for={message <- @messages} class={bubble_class(message.mine)}>
          <p class="whitespace-pre-wrap text-sm">{message.body || "(削除されました)"}</p>
          <p class="mt-1 text-[10px] opacity-60">{format_time(message.inserted_at)}</p>
        </div>

        <p :if={@messages == []} class="text-sm text-zinc-500">
          まだメッセージはありません。
        </p>
      </div>

      <p :if={@refusal} class="mb-2 rounded bg-amber-50 px-3 py-2 text-sm text-amber-900">
        {@refusal}
      </p>

      <form phx-submit="send" class="flex gap-2 border-t border-zinc-200 pt-3">
        <input
          type="text"
          name="body"
          value={@draft}
          autocomplete="off"
          placeholder="メッセージを入力"
          class="flex-1 rounded border-zinc-300 text-sm"
        />
        <button type="submit" class="rounded bg-zinc-900 px-4 py-2 text-sm text-white">送信</button>
      </form>
    </div>
    """
  end

  defp load_messages(user_id, other_id) do
    case Chat.conversation_for(user_id, other_id) do
      nil ->
        []

      conversation ->
        conversation.id
        |> Chat.list_messages()
        |> Enum.map(&Map.put(&1, :mine, &1.sender_id == user_id))
    end
  end

  defp bubble_class(true), do: "ml-auto max-w-[75%] rounded-lg bg-zinc-900 px-3 py-2 text-white"

  defp bubble_class(false), do: "mr-auto max-w-[75%] rounded-lg bg-zinc-100 px-3 py-2 text-zinc-900"

  defp format_time(nil), do: ""
  defp format_time(at), do: Calendar.strftime(at, "%m/%d %H:%M")

  defp humanize(:blocked), do: "この相手にはメッセージを送れません。"
  defp humanize(:not_matched), do: "マッチしていない相手には送れません。"
  defp humanize(:send_limited), do: "現在メッセージの送信が制限されています。"
  defp humanize(:suspended), do: "アカウントが停止されています。"
  defp humanize(:body_too_long), do: "メッセージが長すぎます。"
  defp humanize(_other), do: "送信できませんでした。"
end
