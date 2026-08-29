defmodule NerdMeetWeb.DirectoryController do
  @moduledoc """
  The public directory.

  Search runs in the browser against a published snapshot rather than against a
  query endpoint. The snapshot is a file anyone can download and audit, which
  makes "here is exactly what the directory discloses" a checkable statement
  rather than a promise.
  """
  use NerdMeetWeb, :controller

  alias NerdMeet.Publishing

  def index(conn, _params) do
    render(conn, :index, snapshot: Publishing.latest(), page_title: "ディレクトリ")
  end
end
