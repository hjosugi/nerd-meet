defmodule NerdMeet.Moderation.Rules do
  @moduledoc """
  Stage 1 of the moderation cascade: pattern matching, no I/O, no model.

  This runs synchronously on the send path, so it has to be cheap enough that
  nobody notices it. Everything expensive lives in stages 2 and 3, which run in
  the background on the small fraction of traffic that gets past here.

  The design assumption is that stage 1 is a *warning* far more often than it
  is an enforcement action. Most people who type a phone number are not running
  a scam; they get told the rule and stop. The operators who are running a scam
  get pushed into evasion, and evasion is a much louder signal than the
  original message ever was.

  Returns one of:

    * `{:block, reason}` — refuse the message and tell the sender why
    * `{:flag, reason}` — deliver it, but hand it to stage 2 with a head start
    * `:ok` — deliver it and collect behavioural signals as usual

  See `NerdMeet.Moderation.Text` for why the input is folded before matching.
  """

  alias NerdMeet.Moderation.Text

  # Proximity windows, in bytes. 60 bytes is roughly twenty Japanese
  # characters: enough to span "LINEのIDは" plus a particle or two, short
  # enough that two unrelated sentences do not combine into a violation.
  @window 60

  # Elixir compiles regexes with Unicode properties on, so `\b` treats a
  # Japanese character as a word character and never fires next to one.
  # Latin word boundaries therefore have to be spelled out in ASCII.
  @platform_spaced ~r/(?<![a-z0-9_])(line|kakao|kakaotalk|telegram|discord|wechat|viber|skype|instagram|insta|tiktok|snapchat)(?![a-z0-9_])/
  @platform_squashed ~r/(らいん|かかお|てれぐらむ|でぃすこーど|でぃすこ|いんすた|うぃーちゃっと|すかいぷ|かかおとーく)/u

  @id_marker_spaced ~r/((?<![a-z0-9_])u?id(?![a-z0-9_])|あいでぃ|ゆーざーねーむ|username|こうかん|交換|おしえ|教え|(?<![a-z0-9_])dm(?![a-z0-9_])|でぃーえむ)/u
  @id_token ~r/[a-z0-9][a-z0-9_.\-]{2,}/

  # A glued form needs no proximity check: nobody writes "lineid" by accident.
  @platform_glued ~r/(らいんid|らいんあいでぃ|lineid|kakaoid|telegramid|discordid|instaid|line＠|line@)/u

  @email ~r/[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}/
  # A social handle: an @ that is not part of an email address.
  @handle ~r/(^|[^a-z0-9._%+\-])@[a-z0-9_]{3,}/
  # Japanese landline and mobile numbers, matched after separators are removed.
  @phone ~r/(?<!\d)0\d{9,10}(?!\d)/
  @url ~r/(https?:\/\/|www\.)|((?<![a-z0-9\-])[a-z0-9\-]+\.(com|net|org|jp|io|me|co|xyz|link|app|dev|to|gg)(?![a-z0-9]))/

  # Claiming to be a minor on an account that cleared adult verification is
  # either a lie or a stolen account. Both are worth stopping.
  # The bare-number forms are deliberately narrow: "集中3時間" must not read as
  # a claim to be in the third year of junior high.
  @minor_claim ~r/(じぇーけー|(?<![a-z0-9_])jk(?![a-z0-9_])|じぇーしー|(?<![a-z0-9_])jc(?![a-z0-9_])|じょしこうせい|女子高生|中学生|ちゅうがくせい|小学生|しょうがくせい|(中|高)[1-3](年|生|です)|未成年|みせいねん|18歳未満|18さいみまん)/u

  # Terms whose only use in this context is to price a meeting.
  @solicitation ~r/(ほ別|ほべつ|ぱぱ活|ぱぱかつ|ままかつ|わりきり|割り切り|割切|えんこう|援交|てあて|手当|おとなのかんけい|大人の関係|即即|そくそく|さぽ(?!ーと|ーたー|ーとし))/u
  @money ~r/([0-9]+(まん|万|えん|円|k|千)|[0-9]+こ|こづかい|お小遣い)/u

  @doc """
  Classifies a single message body.

  `opts` is accepted for callers that have extra context to bring; it is
  currently unused and exists so that adding, say, the sender's verified age
  does not change the call sites.
  """
  @spec check(binary(), keyword()) :: {:block, binary()} | {:flag, binary()} | :ok
  def check(body, opts \\ [])

  def check(body, _opts) when is_binary(body) do
    %{spaced: spaced, squashed: squashed} = Text.forms(body)

    cond do
      Regex.match?(@minor_claim, squashed) -> {:block, "minor_claim"}
      Regex.match?(@solicitation, squashed) -> {:block, "solicitation"}
      Regex.match?(@email, spaced) -> {:block, "email_address"}
      Regex.match?(@phone, squashed) -> {:block, "phone_number"}
      Regex.match?(@handle, spaced) -> {:block, "social_handle"}
      Regex.match?(@platform_glued, squashed) -> {:block, "external_contact"}
      contact_exchange?(spaced, squashed) -> {:block, "external_contact"}
      money_for_meeting?(squashed) -> {:flag, "priced_meeting"}
      Regex.match?(@url, spaced) -> {:flag, "external_url"}
      platform_mention?(spaced, squashed) -> {:flag, "platform_mention"}
      true -> :ok
    end
  end

  @doc """
  The sentence shown to the sender when a message is refused.

  Saying which rule was hit is deliberate. A person who did not know the rule
  now does; an operator learns only what they would have learned from one more
  attempt anyway.
  """
  @spec explain(binary()) :: binary()
  def explain("minor_claim"), do: "年齢に関する記述のため送信できません。"

  def explain("solicitation"), do: "金銭を伴う交際を示唆する表現は送信できません。"

  def explain("email_address"), do: "メールアドレスは交換できません。マッチ後のチャット内でやり取りしてください。"

  def explain("phone_number"), do: "電話番号は交換できません。マッチ後のチャット内でやり取りしてください。"

  def explain("social_handle"), do: "外部サービスのアカウントは交換できません。"

  def explain("external_contact"), do: "外部の連絡先は交換できません。マッチ後のチャット内でやり取りしてください。"

  def explain(_other), do: "この内容は送信できません。"

  defp contact_exchange?(spaced, squashed) do
    Text.near?(spaced, @platform_spaced, @id_marker_spaced, @window) or
      Text.near?(squashed, @platform_squashed, @id_marker_spaced, @window) or
      (Regex.match?(@platform_spaced, spaced) and Regex.match?(@id_token, spaced) and
         Regex.match?(@id_marker_spaced, spaced))
  end

  defp platform_mention?(spaced, squashed) do
    Regex.match?(@platform_spaced, spaced) or Regex.match?(@platform_squashed, squashed)
  end

  defp money_for_meeting?(squashed) do
    Regex.match?(@money, squashed) and
      Regex.match?(~r/(あ[うえ]る?|会[うえ]|ほてる|でーと|よる|夜|時間|じかん)/u, squashed)
  end
end
