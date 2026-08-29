defmodule NerdMeetWeb.HealthController do
  @moduledoc "Liveness and readiness, kept boring on purpose."
  use NerdMeetWeb, :controller

  alias Ecto.Adapters.SQL
  alias NerdMeet.Repo

  def show(conn, _params) do
    case SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> json(conn, %{status: "ok", database: "ok"})
      {:error, _reason} -> conn |> put_status(503) |> json(%{status: "degraded"})
    end
  end
end
