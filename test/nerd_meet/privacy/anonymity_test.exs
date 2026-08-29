defmodule NerdMeet.Privacy.AnonymityTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Nerd.Demo
  alias NerdMeet.Privacy.Anonymity

  describe "the k floor" do
    test "no published group is ever smaller than k" do
      report = 5_000 |> Demo.synthetic_rows() |> Anonymity.analyze(k: 5)

      assert report.violations == 0
    end

    test "a row that cannot reach k at any band is withheld entirely" do
      # One person from a prefecture nobody else is in, among a crowd that all
      # share one.
      crowd =
        for i <- 1..50 do
          %{prefecture: "東京都", birth_year: 1990, years_experience: 8, display_name: "c#{i}"}
        end

      loner = %{
        prefecture: "鳥取県",
        birth_year: 1948,
        years_experience: 41,
        display_name: "alone"
      }

      result = Anonymity.anonymize([loner | crowd], k: 5)

      refute Enum.any?(result.rows, &(&1.display_name == "alone"))
      assert result.suppressed == 1
    end

    test "exact quasi-identifiers never survive publication" do
      result = 2_000 |> Demo.synthetic_rows() |> Anonymity.anonymize(k: 5)

      for row <- result.rows do
        refute Map.has_key?(row, :prefecture)
        refute Map.has_key?(row, :birth_year)
        refute Map.has_key?(row, :years_experience)
        assert row.area
        assert row.age_band
      end
    end
  end

  describe "the density requirement" do
    test "a small directory loses almost all of its precision" do
      small = 300 |> Demo.synthetic_rows() |> Anonymity.analyze(k: 5)

      # Not a bug and not a tuning problem: at this population most
      # combinations of area, age and experience describe one or two people, so
      # the fine band is unpublishable no matter how the code is written. The
      # rows still appear, banded coarsely, which is the difference between a
      # directory that is vague and one that is empty.
      assert small.fine_ratio < 0.25
      assert small.published_ratio > 0.95
      assert small.violations == 0
    end

    test "the same code keeps far more precision once the population grows" do
      small = 300 |> Demo.synthetic_rows() |> Anonymity.analyze(k: 5)
      large = 6_000 |> Demo.synthetic_rows() |> Anonymity.analyze(k: 5)

      assert small.fine_ratio < 0.25
      assert large.fine_ratio > 0.8
      assert Map.get(large.by_band, :fine, 0) > 0
      assert large.violations == 0
    end
  end

  describe "region/1" do
    test "prefectures widen into regions" do
      assert Anonymity.region("東京都") == "関東"
      assert Anonymity.region("沖縄県") == "九州・沖縄"
      assert Anonymity.region(nil) == "不明"
    end
  end
end
