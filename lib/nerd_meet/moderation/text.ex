defmodule NerdMeet.Moderation.Text do
  @moduledoc """
  Normalisation for Japanese moderation input.

  Evasion in Japanese is overwhelmingly a matter of changing the *shape* of a
  word rather than the word itself: full-width letters, katakana instead of
  latin, a space wedged between every character, a particle dropped in the
  middle. Matching raw input against a word list therefore catches almost
  nothing. Everything here runs before a single pattern is applied.

  Two forms come out of this module and both are searched:

    * `normalize/1` keeps spacing, so latin word boundaries still work. This is
      the form where `\\bline\\b` can be told apart from `pipeline`.
    * `squash/1` removes every separator, so the spaced-out form of a platform
      name collapses back into one token. Word boundaries are gone here, which
      is why only patterns that cannot appear inside an ordinary word are
      matched against it.
  """

  # Words that legitimately end in ライン. Without masking these first, every
  # "オンライン勉強会" in the directory reads as an attempt to swap LINE IDs.
  @masked_compounds ~w(
    おんらいん たいむらいん ぱいぷらいん がいどらいん でっどらいん あうとらいん
    えんじんらいん すとーりーらいん こまんどらいん べーすらいん とっぷらいん
    ぼーだーらいん でざいんらいん
  )

  # A character that cannot occur in user input after normalisation, used to
  # blank out a compound while keeping its length.
  @mask_char "�"

  # Separators an evader sprinkles between characters. The katakana prolonged
  # sound mark is deliberately absent: removing it would make サポート
  # indistinguishable from サポ.
  @separators ~r/[\s\p{Z}\p{C}・･、。,\.\-–—~〜_＿\*＊\|｜\/\\'"“”‘’`()（）\[\]{}「」『』【】!！\?？:：;；#＃\+＝=]/u

  @doc """
  NFKC-folds, lower-cases and converts katakana to hiragana.

  NFKC alone handles the full-width tricks (`Ｊ　Ｋ` becomes `J K`, the
  ideographic space becomes an ordinary one). The katakana fold is what makes a
  single pattern cover both `ライン` and `らいん`.
  """
  @spec normalize(binary()) :: binary()
  def normalize(text) when is_binary(text) do
    text
    |> :unicode.characters_to_nfkc_binary()
    |> String.downcase()
    |> katakana_to_hiragana()
  end

  @doc """
  Collapses a normalised string to its separator-free form.
  """
  @spec squash(binary()) :: binary()
  def squash(normalized) when is_binary(normalized) do
    String.replace(normalized, @separators, "")
  end

  @doc """
  Blanks out words that merely contain a platform name.

  The replacement is the same length as the original so that any index-based
  proximity check stays honest.
  """
  @spec mask_compounds(binary()) :: binary()
  def mask_compounds(text) when is_binary(text) do
    Enum.reduce(@masked_compounds, text, fn word, acc ->
      String.replace(acc, word, String.duplicate(@mask_char, String.length(word)))
    end)
  end

  @doc """
  Both searchable forms of a message, computed once.
  """
  @spec forms(binary()) :: %{spaced: binary(), squashed: binary()}
  def forms(text) when is_binary(text) do
    normalized = text |> normalize() |> mask_compounds()

    %{spaced: normalized, squashed: squash(normalized)}
  end

  @doc """
  True when a match of `left` and a match of `right` occur within `window`
  bytes of each other. Byte distance is used rather than character distance
  because that is what `Regex.scan/3` reports; a Japanese character is three
  bytes, so pick windows accordingly.

  Presence alone is too blunt: a message can mention Discord in one paragraph
  and the word "ID" in another without the two having anything to do with each
  other. Proximity is what separates talking about a platform from handing over
  an account on it.
  """
  @spec near?(binary(), Regex.t(), Regex.t(), pos_integer()) :: boolean()
  def near?(text, left, right, window) do
    lefts = index_of(left, text)
    rights = index_of(right, text)

    Enum.any?(lefts, fn {ls, ll} ->
      Enum.any?(rights, fn {rs, rl} ->
        if rs >= ls, do: rs - (ls + ll) <= window, else: ls - (rs + rl) <= window
      end)
    end)
  end

  defp index_of(regex, text) do
    case Regex.scan(regex, text, return: :index) do
      [] -> []
      matches -> Enum.map(matches, &hd/1)
    end
  end

  defp katakana_to_hiragana(text) do
    text
    |> String.to_charlist()
    |> Enum.map(fn
      cp when cp in 0x30A1..0x30F6 -> cp - 0x60
      cp -> cp
    end)
    |> List.to_string()
  end
end
