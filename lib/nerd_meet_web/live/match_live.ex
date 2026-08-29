defmodule NerdMeetWeb.MatchLive do
  @moduledoc "The list of people who chose you back."
  use NerdMeetWeb, :live_view

  alias NerdMeet.Chat
  alias NerdMeet.Members
  alias NerdMeet.Social

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, matches: load_matches(socket.assigns.current_user), page_title: "マッチ")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-10">
      <h1 class="text-2xl font-semibold text-zinc-900">マッチ</h1>
      <p class="mt-2 text-sm text-zinc-600">
        相互にいいねした相手だけが表示されます。会話はここからしか始まりません。
      </p>

      <ul class="mt-6 divide-y divide-zinc-200">
        <li :for={match <- @matches} class="flex items-center justify-between py-4">
          <div>
            <p class="font-medium text-zinc-900">{match.display_name}</p>
            <p class="text-sm text-zinc-500">{match.headline}</p>
          </div>
          <.link
            navigate={~p"/chat/#{match.user_id}"}
            class="rounded bg-zinc-900 px-3 py-1.5 text-sm text-white"
          >
            会話を開く
          </.link>
        </li>
      </ul>

      <p :if={@matches == []} class="mt-8 rounded bg-zinc-50 px-4 py-6 text-sm text-zinc-600">
        まだマッチがありません。ディレクトリで条件を絞って探してみてください。
      </p>
    </div>
    """
  end

  defp load_matches(nil), do: []

  defp load_matches(user) do
    user.id
    |> Social.list_matches()
    |> Enum.map(fn match ->
      other_id = Social.counterpart(match, user.id)
      profile = Members.get_profile(other_id)

      %{
        user_id: other_id,
        display_name: (profile && profile.display_name) || "(退会済み)",
        headline: (profile && profile.headline) || "",
        conversation: Chat.conversation_for(user.id, other_id)
      }
    end)
  end
end
