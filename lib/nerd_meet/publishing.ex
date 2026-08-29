defmodule NerdMeet.Publishing do
  @moduledoc """
  Static exports of the anonymised directory.

  Search runs client-side over a published snapshot rather than as a query
  against live data. That is not a performance trick. A snapshot is a fixed,
  inspectable artefact: anyone can download it and check what the directory
  actually discloses, which is a claim a server-side search API can never make
  about itself.

  The snapshot only ever contains rows that survived
  `NerdMeet.Privacy.Anonymity`, and the fields it writes are enumerated in one
  place below so that adding a column to `profiles` cannot silently add a
  column to the export.
  """

  alias NerdMeet.Members
  alias NerdMeet.Privacy.Anonymity
  alias NerdMeet.Publishing.Snapshot
  alias NerdMeet.Repo

  # Everything the export is allowed to contain. Any field not named here does
  # not leave the database.
  @exported_fields [
    :display_name,
    :headline,
    :band,
    :area,
    :age_band,
    :experience_band,
    :remote_ok,
    :languages,
    :skills,
    :tools
  ]

  @doc "Fields the snapshot may contain, in the order they are written."
  @spec exported_fields() :: [atom()]
  def exported_fields, do: @exported_fields

  @doc """
  Builds a snapshot from current directory rows and writes it to disk.
  """
  @spec generate(keyword()) :: {:ok, Snapshot.t(), binary()} | {:error, term()}
  def generate(opts \\ []) do
    slug = opts |> Keyword.get(:slug, "directory") |> sanitize_slug()
    rows = Keyword.get_lazy(opts, :rows, &Members.directory_rows/0)
    result = Anonymity.anonymize(rows, opts)

    payload = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "k" => result.k,
      "count" => length(result.rows),
      "suppressed" => result.suppressed,
      "fields" => Enum.map(@exported_fields, &to_string/1),
      "rows" => Enum.map(result.rows, &export_row/1)
    }

    json = Jason.encode!(payload)
    path = Path.join(directory(), "#{slug}.json")
    File.mkdir_p!(directory())
    File.write!(path, json)

    attrs = %{
      slug: slug,
      generated_at: DateTime.utc_now(),
      record_count: length(result.rows),
      suppressed_count: result.suppressed,
      k: result.k,
      byte_size: byte_size(json),
      checksum: :sha256 |> :crypto.hash(json) |> Base.encode16(case: :lower)
    }

    %Snapshot{}
    |> Snapshot.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :slug]},
      conflict_target: :slug,
      returning: true
    )
    |> case do
      {:ok, snapshot} -> {:ok, snapshot, path}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Where snapshots are written. Served as a static asset."
  @spec directory() :: binary()
  def directory do
    Application.get_env(:nerd_meet, :snapshot_dir) ||
      Path.join(:code.priv_dir(:nerd_meet), "static/snapshots")
  end

  @spec latest(binary()) :: Snapshot.t() | nil
  def latest(slug \\ "directory"), do: Repo.get_by(Snapshot, slug: slug)

  # The slug reaches a filesystem path, so it is restricted to a shape that
  # cannot climb out of the snapshot directory rather than merely checked for
  # "..".
  defp sanitize_slug(slug) do
    case Regex.run(~r/\A[a-z0-9][a-z0-9\-_]{0,63}\z/, to_string(slug)) do
      [valid] -> valid
      nil -> raise ArgumentError, "invalid snapshot slug: #{inspect(slug)}"
    end
  end

  defp export_row(row) do
    Map.new(@exported_fields, fn field -> {to_string(field), Map.get(row, field)} end)
  end
end
