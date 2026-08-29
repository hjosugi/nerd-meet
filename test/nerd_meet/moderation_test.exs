defmodule NerdMeet.ModerationTest do
  use NerdMeet.DataCase, async: true

  alias NerdMeet.Chat
  alias NerdMeet.Chat.Message
  alias NerdMeet.Fixtures
  alias NerdMeet.Moderation
  alias NerdMeet.Moderation.Signals
  alias NerdMeet.Privacy.Deletion
  alias NerdMeet.Social

  describe "stage 2 sees what stage 1 cannot" do
    test "the same message sent to many people scores as templated" do
      operator = Fixtures.member()

      # Nothing here trips a single stage 1 rule. Every message is polite,
      # on-topic and free of contact details. What gives it away is that there
      # are twelve of them and they are the same message.
      for _i <- 1..12 do
        target = Fixtures.member()
        {:ok, _a} = Social.like(operator.id, target.id)
        {:ok, _b} = Social.like(target.id, operator.id)

        {:ok, _message} =
          Chat.send_message(
            operator.id,
            target.id,
            "はじめまして！プロフィール拝見しました。よかったらお話ししませんか？"
          )
      end

      assessment = Signals.assess(operator.id)

      assert "high_fanout" in assessment.reasons
      assert "templated_messages" in assessment.reasons
      assert "instant_openers" in assessment.reasons
      assert assessment.score >= 60
    end

    test "an ordinary member with one conversation scores nothing" do
      {a, b} = Fixtures.matched_pair()
      {:ok, _first} = Chat.send_message(a.id, b.id, "Ectoのマイグレーションの話しませんか")
      {:ok, _second} = Chat.send_message(a.id, b.id, "週末は勉強会に行っていました")

      assessment = Signals.assess(a.id)

      assert assessment.score == 0
      assert assessment.reasons == []
    end

    test "reports from several people are a signal on their own" do
      subject = Fixtures.member()

      for _i <- 1..3 do
        reporter = Fixtures.member()
        {:ok, _report} = Social.report(reporter.id, subject.id, "spam")
      end

      assessment = Signals.assess(subject.id)

      assert "reported_by_many" in assessment.reasons
    end
  end

  describe "enforcement" do
    test "a high score applies a shadow limit rather than a ban" do
      operator = Fixtures.member()

      for _i <- 1..12 do
        target = Fixtures.member()
        {:ok, _a} = Social.like(operator.id, target.id)
        {:ok, _b} = Social.like(target.id, operator.id)
        {:ok, _m} = Chat.send_message(operator.id, target.id, "はじめまして！お話ししませんか？")
      end

      assert {:ok, review} = Moderation.review_account(operator.id)
      assert review.stage == "signals"
      assert Moderation.restricted?(operator.id, "shadow_limit")

      # Shadow limited, not suspended: the account still works, and stops
      # appearing in the directory.
      refute Moderation.restricted?(operator.id, "suspension")
      assert Repo.get!(NerdMeet.Accounts.User, operator.id).status == "active"
    end

    test "a quiet account is left alone" do
      {a, b} = Fixtures.matched_pair()
      {:ok, _message} = Chat.send_message(a.id, b.id, "こんにちは")

      assert {:ok, :clear} = Moderation.review_account(a.id)
      assert Moderation.active_enforcements(a.id) == []
    end

    test "a shadow-limited account disappears from search" do
      member = Fixtures.member(%{skills: ["elixir"], years_experience: 9})
      filter = %{"all" => [%{"field" => "skills", "op" => "contains", "value" => "elixir"}]}

      before = NerdMeet.Members.search(filter, k: 1)
      assert Enum.any?(before.rows, &(&1.display_name == member.handle))

      {:ok, _enforcement} = Moderation.apply_enforcement(member.id, "shadow_limit", "test")
      after_limit = NerdMeet.Members.search(filter, k: 1)

      refute Enum.any?(after_limit.rows, &(&1.display_name == member.handle))
    end
  end

  describe "reading plaintext" do
    test "every read writes an audit row with a reason" do
      {a, b} = Fixtures.matched_pair()
      reviewer = Fixtures.member()
      {:ok, message} = Chat.send_message(a.id, b.id, "監査対象のメッセージ")
      stored = Repo.get!(Message, message.id)

      assert {:ok, "監査対象のメッセージ"} =
               Moderation.read_plaintext(reviewer.id, stored, "通報#1234の調査")

      [entry] = Moderation.audit_trail("message", message.id)
      assert entry.actor_id == reviewer.id
      assert entry.action == "message.read_plaintext"
      assert entry.reason == "通報#1234の調査"
    end

    test "an empty reason is refused, so the log cannot be filled with noise" do
      reviewer = Fixtures.member()

      assert {:error, changeset} =
               Moderation.audit(reviewer.id, "message.read_plaintext", "message", nil, "x")

      assert errors_on(changeset).reason
    end

    test "a shredded message cannot be read at all" do
      {a, b} = Fixtures.matched_pair()
      reviewer = Fixtures.member()
      {:ok, message} = Chat.send_message(a.id, b.id, "消えたメッセージ")
      Deletion.shred_conversation(message.conversation_id)

      assert {:error, :unreadable} =
               Moderation.read_plaintext(
                 reviewer.id,
                 Repo.get!(Message, message.id),
                 "通報の調査"
               )
    end
  end
end
