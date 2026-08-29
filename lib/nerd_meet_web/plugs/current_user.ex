defmodule NerdMeetWeb.Plugs.CurrentUser do
  @moduledoc """
  Loads the signed-in member from the session.

  The passkey ceremony that puts a user id in the session lives in the browser
  and is not built yet; `NerdMeet.Accounts.authenticate/4` is the server half
  and is tested directly. Until the ceremony exists, only the development
  sign-in route below writes to the session, and it is compiled out of any
  build where `:dev_routes` is false.
  """
  import Plug.Conn

  alias NerdMeet.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user =
      case get_session(conn, :user_id) do
        nil -> nil
        id -> Accounts.get_user(id)
      end

    conn
    |> assign(:current_user, user)
    |> put_session(:user_id, user && user.id)
  end

  @doc "Halts with a redirect when there is nobody signed in."
  def require_member(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "サインインが必要です")
      |> Phoenix.Controller.redirect(to: "/")
      |> halt()
    end
  end

  @doc "Makes the current user available to LiveViews mounted under this session."
  def on_mount(:current_user, _params, %{"user_id" => user_id}, socket) do
    {:cont, Phoenix.Component.assign_new(socket, :current_user, fn -> Accounts.get_user(user_id) end)}
  end

  def on_mount(:current_user, _params, _session, socket) do
    {:cont, Phoenix.Component.assign(socket, :current_user, nil)}
  end
end
