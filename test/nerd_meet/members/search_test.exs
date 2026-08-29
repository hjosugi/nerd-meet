defmodule NerdMeet.Members.SearchTest do
  use NerdMeet.DataCase, async: true

  alias NerdMeet.Fixtures
  alias NerdMeet.Members
  alias NerdMeet.Members.Search

  @elixir_filter %{
    "all" => [
      %{"field" => "skills", "op" => "any", "value" => ["elixir", "erlang"]},
      %{"field" => "years_experience", "op" => "gte", "value" => 3},
      %{"field" => "remote_ok", "op" => "eq", "value" => true}
    ]
  }

  describe "validation" do
    test "a known field with a sensible operator is accepted" do
      assert :ok = Search.validate(@elixir_filter)
    end

    test "an unknown field is refused" do
      filter = %{"all" => [%{"field" => "password", "op" => "eq", "value" => "x"}]}

      assert {:error, message} = Search.validate(filter)
      assert message =~ "password"
    end

    test "an array operator on a scalar field is refused" do
      filter = %{"all" => [%{"field" => "prefecture", "op" => "any", "value" => ["東京都"]}]}

      assert {:error, _message} = Search.validate(filter)
    end

    test "an unbounded condition list is refused" do
      conditions =
        for _i <- 1..20, do: %{"field" => "remote_ok", "op" => "eq", "value" => true}

      assert {:error, _message} = Search.validate(%{"all" => conditions})
    end

    test "an invalid filter cannot be stored" do
      user = Fixtures.member()
      filter = %{"all" => [%{"field" => "id", "op" => "eq", "value" => "x"}]}

      assert {:error, changeset} =
               Members.create_saved_query(user.id, %{name: "bad", filter: filter})

      assert errors_on(changeset).filter
    end
  end

  describe "to_sql/1" do
    test "renders a filter as the SQL it stands for" do
      sql = Search.to_sql(@elixir_filter)

      assert sql =~ "SELECT * FROM profiles"
      assert sql =~ "skills && ARRAY['elixir', 'erlang']"
      assert sql =~ "years_experience >= 3"
      assert sql =~ "remote_ok = true"
    end

    test "quotes are escaped so a rendered condition stays readable" do
      filter = %{"all" => [%{"field" => "prefecture", "op" => "eq", "value" => "O'Hara"}]}

      assert Search.to_sql(filter) =~ "'O''Hara'"
    end
  end

  describe "search/2" do
    test "finds members matching the conditions" do
      wanted = Fixtures.member(%{skills: ["elixir"], years_experience: 9, remote_ok: true})
      _other = Fixtures.member(%{skills: ["cobol"], years_experience: 9, remote_ok: true})

      result = Members.search(@elixir_filter, k: 1)

      assert Enum.any?(result.rows, &(&1.display_name == wanted.handle))
      refute Enum.any?(result.rows, &(&1.display_name == "cobol"))
    end

    test "results are anonymised, not raw rows" do
      Fixtures.member(%{skills: ["elixir"], years_experience: 9})

      result = Members.search(@elixir_filter, k: 1)

      for row <- result.rows do
        refute Map.has_key?(row, :prefecture)
        assert row.area
        assert row.band
      end
    end

    test "the viewer is excluded from their own results" do
      me = Fixtures.member(%{skills: ["elixir"], years_experience: 9})

      result = Members.search(@elixir_filter, k: 1, viewer_id: me.id)

      refute Enum.any?(result.rows, &(&1.display_name == me.handle))
    end
  end

  describe "mutual_query_matches/2" do
    test "returns only people who fit you while you fit them" do
      me = Fixtures.member(%{skills: ["elixir"], years_experience: 10, remote_ok: true})
      them = Fixtures.member(%{skills: ["elixir"], years_experience: 12, remote_ok: true})
      mismatched = Fixtures.member(%{skills: ["elixir"], years_experience: 1, remote_ok: true})

      wants_experience = %{
        "all" => [%{"field" => "years_experience", "op" => "gte", "value" => 5}]
      }

      {:ok, _mine} =
        Members.create_saved_query(me.id, %{
          name: "経験5年以上",
          filter: wants_experience,
          published: true
        })

      {:ok, _theirs} =
        Members.create_saved_query(them.id, %{
          name: "経験5年以上",
          filter: wants_experience,
          published: true
        })

      # This one wants what I am, but is not what I want.
      {:ok, _junior} =
        Members.create_saved_query(mismatched.id, %{
          name: "経験5年以上",
          filter: wants_experience,
          published: true
        })

      matches = Members.mutual_query_matches(me.id)
      ids = Enum.map(matches, & &1.user_id)

      assert them.id in ids
      refute mismatched.id in ids
      refute me.id in ids
    end

    test "an unpublished query matches nobody" do
      me = Fixtures.member(%{years_experience: 10})
      Fixtures.member(%{years_experience: 12})

      {:ok, _private} =
        Members.create_saved_query(me.id, %{
          name: "非公開",
          filter: %{"all" => [%{"field" => "years_experience", "op" => "gte", "value" => 5}]},
          published: false
        })

      assert Members.mutual_query_matches(me.id) == []
    end
  end
end
