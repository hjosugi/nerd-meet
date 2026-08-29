defmodule NerdMeet.Moderation.RulesTest do
  use ExUnit.Case, async: true

  alias NerdMeet.Moderation.Rules
  alias NerdMeet.Moderation.Text

  describe "evasion in Japanese" do
    test "full-width characters are folded before matching" do
      assert {:block, "minor_claim"} = Rules.check("Ｊ　Ｋです")
    end

    test "a name spaced out one character at a time still matches" do
      assert {:block, "external_contact"} = Rules.check("ら　い　ん　ＩＤ　教えて")
    end

    test "particles wedged between the words do not break the match" do
      assert {:block, "external_contact"} = Rules.check("LINE の ID は abc_123 です")
    end

    test "katakana and latin spellings are the same rule" do
      assert {:block, "external_contact"} = Rules.check("カカオのID交換しませんか")
      assert {:block, "external_contact"} = Rules.check("kakao id 交換しませんか")
    end
  end

  describe "contact details" do
    test "phone numbers survive any separator" do
      assert {:block, "phone_number"} = Rules.check("090-1234-5678")
      assert {:block, "phone_number"} = Rules.check("０９０ １２３４ ５６７８")
    end

    test "email addresses are refused" do
      assert {:block, "email_address"} = Rules.check("foo.bar@example.com までどうぞ")
    end

    test "social handles are refused" do
      assert {:block, "social_handle"} = Rules.check("@example_user までDMください")
    end
  end

  describe "solicitation" do
    test "priced meeting slang is refused" do
      assert {:block, "solicitation"} = Rules.check("ホ別2で")
      assert {:block, "solicitation"} = Rules.check("パパ活の相手募集")
    end

    test "サポ is refused but サポート is not" do
      assert {:block, "solicitation"} = Rules.check("サポしてくれる人募集")
      assert :ok = Rules.check("インフラのサポートをやっています")
    end
  end

  describe "messages that must pass" do
    test "ordinary engineering conversation is untouched" do
      assert :ok = Rules.check("こんにちは、Elixir書いてます")
      assert :ok = Rules.check("PostgreSQLのインデックス設計の話しませんか")
      assert :ok = Rules.check("明日の勉強会いきます？")
    end

    test "オンライン does not read as a LINE exchange" do
      assert :ok = Rules.check("オンライン勉強会いきます？")
      assert :ok = Rules.check("タイムラインの実装の話がしたい")
    end

    test "a platform mentioned without an identifier is flagged, not blocked" do
      assert {:flag, "platform_mention"} = Rules.check("Discordのサーバーありますか")
    end

    test "a link is flagged so stage 2 sees it, but still delivered" do
      assert {:flag, "external_url"} = Rules.check("https://example.com/blog を書きました")
    end
  end

  describe "normalisation" do
    test "katakana folds to hiragana and full width folds to half" do
      assert Text.normalize("ラインＩＤ") == "らいんid"
    end

    test "squashing removes separators but keeps the prolonged sound mark" do
      assert Text.squash(Text.normalize("サ ポ ー ト")) == "さぽーと"
    end
  end

  describe "explain/1" do
    test "every block reason has a sentence for the sender" do
      for reason <- ~w(minor_claim solicitation email_address phone_number social_handle
                       external_contact) do
        assert is_binary(Rules.explain(reason))
        assert String.length(Rules.explain(reason)) > 5
      end
    end
  end
end
