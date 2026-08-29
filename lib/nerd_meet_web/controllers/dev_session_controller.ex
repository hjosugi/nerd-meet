defmodule NerdMeetWeb.DevSessionController do
  @moduledoc """
  A development-only way to hold a session.

  This exists so the authenticated screens can be worked on before the browser
  half of the passkey ceremony lands. It is routed only when `:dev_routes` is
  true and must never be reachable anywhere real.
  """
  use NerdMeetWeb, :controller

  alias NerdMeet.Accounts

  def create(conn, %{"handle" => handle}) do
    case Accounts.get_user_by_handle(handle) do
      nil ->
        conn |> put_flash(:error, "#{handle} は存在しません") |> redirect(to: ~p"/")

      user ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "#{user.handle} としてサインインしました（開発用）")
        |> redirect(to: ~p"/matches")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end
end
