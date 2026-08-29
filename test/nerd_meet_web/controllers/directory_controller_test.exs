defmodule NerdMeetWeb.DirectoryControllerTest do
  use NerdMeetWeb.ConnCase, async: true

  test "the directory page renders and says how it works", %{conn: conn} do
    conn = get(conn, ~p"/directory")
    body = html_response(conn, 200)

    assert body =~ "ディレクトリ"
    assert body =~ "ブラウザ内で"
  end

  test "health reports the database", %{conn: conn} do
    assert %{"status" => "ok", "database" => "ok"} =
             conn |> get(~p"/health") |> json_response(200)
  end

  test "the published snapshot is downloadable", %{conn: conn} do
    dir = Path.join(:code.priv_dir(:nerd_meet), "static/snapshots")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "directory.json"), ~s({"rows":[]}))
    on_exit(fn -> File.rm(Path.join(dir, "directory.json")) end)

    conn = get(conn, "/snapshots/directory.json")

    assert response(conn, 200) =~ "rows"
  end

  test "the home page links to the source", %{conn: conn} do
    body = conn |> get(~p"/") |> html_response(200)

    assert body =~ "nerd-meet"
    assert body =~ "github.com/hjosugi/nerd-meet"
  end
end
