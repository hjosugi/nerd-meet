defmodule NerdMeetWeb.PageControllerTest do
  use NerdMeetWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "顔写真ではなく条件で探す"
  end
end
