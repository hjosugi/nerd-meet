defmodule NerdMeet.PublishingTest do
  use NerdMeet.DataCase, async: false

  alias Mix.Tasks.Nerd.Demo
  alias NerdMeet.Fixtures
  alias NerdMeet.Publishing

  setup do
    dir = Path.join(System.tmp_dir!(), "nerd-snapshots-#{System.unique_integer([:positive])}")
    Application.put_env(:nerd_meet, :snapshot_dir, dir)

    on_exit(fn ->
      Application.delete_env(:nerd_meet, :snapshot_dir)
      File.rm_rf(dir)
    end)

    %{dir: dir}
  end

  test "the snapshot only contains fields on the export list" do
    {:ok, _snapshot, path} = Publishing.generate(rows: Demo.synthetic_rows(2_000), k: 5)
    payload = path |> File.read!() |> Jason.decode!()
    allowed = Enum.map(Publishing.exported_fields(), &to_string/1)

    for row <- payload["rows"] do
      assert Map.keys(row) -- allowed == []
    end
  end

  test "no exact quasi-identifier reaches the file" do
    {:ok, _snapshot, path} = Publishing.generate(rows: Demo.synthetic_rows(2_000), k: 5)
    json = File.read!(path)

    refute json =~ ~s("prefecture")
    refute json =~ ~s("birth_year")
    refute json =~ ~s("years_experience")
    refute json =~ ~s("user_id")
  end

  test "a real member's identifiers are not in the export" do
    member = Fixtures.member(%{display_name: "publisher", prefecture: "東京都"})
    {:ok, _snapshot, path} = Publishing.generate(k: 1)
    json = File.read!(path)

    assert json =~ "publisher"
    refute json =~ member.id
  end

  test "the recorded size and checksum describe the file that was written" do
    {:ok, snapshot, path} = Publishing.generate(rows: Demo.synthetic_rows(500), k: 5)
    json = File.read!(path)

    assert snapshot.byte_size == byte_size(json)
    assert snapshot.checksum == :sha256 |> :crypto.hash(json) |> Base.encode16(case: :lower)
    assert snapshot.record_count + snapshot.suppressed_count == 500
  end

  test "regenerating updates the same slug instead of piling up rows" do
    {:ok, first, _path} = Publishing.generate(rows: Demo.synthetic_rows(100), k: 5)
    {:ok, second, _path} = Publishing.generate(rows: Demo.synthetic_rows(200), k: 5)

    assert first.id == second.id
    assert second.record_count > first.record_count
  end
end
