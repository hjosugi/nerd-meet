defmodule NerdMeet.Members.Search do
  @moduledoc """
  The structured query language behind directory search and published queries.

  A filter is a map, never a string, and every field name is checked against a
  whitelist before it reaches a query. Users write conditions; they never write
  SQL. The SQL shown on a profile is rendered *from* the map by `to_sql/1` so
  that a condition can be read and argued with, which is the entire point of
  publishing one.

      %{"all" => [
        %{"field" => "skills", "op" => "any", "value" => ["elixir", "erlang"]},
        %{"field" => "years_experience", "op" => "gte", "value" => 3},
        %{"field" => "remote_ok", "op" => "eq", "value" => true}
      ]}

  renders as

      SELECT * FROM profiles
       WHERE skills && ARRAY['elixir','erlang']
         AND years_experience >= 3
         AND remote_ok = true
  """

  import Ecto.Query

  alias NerdMeet.Members.Profile

  @array_fields ~w(skills tools languages)
  @scalar_fields ~w(prefecture region years_experience birth_year remote_ok)
  @fields @array_fields ++ @scalar_fields

  @array_ops ~w(any all_of contains)
  @scalar_ops ~w(eq neq gte lte in)

  @max_conditions 12

  @doc "Fields a condition may name."
  @spec fields() :: [binary()]
  def fields, do: @fields

  @doc """
  Checks a filter without touching the database.

  Called from the changeset, so an invalid filter can never be stored, and
  therefore never has to be defended against at query time.
  """
  @spec validate(map()) :: :ok | {:error, binary()}
  def validate(%{} = filter) do
    conditions = Map.get(filter, "all", Map.get(filter, :all, []))

    cond do
      not is_list(conditions) ->
        {:error, ~s(条件は "all" のリストで指定してください)}

      length(conditions) > @max_conditions ->
        {:error, "条件は#{@max_conditions}個までです"}

      true ->
        Enum.reduce_while(conditions, :ok, fn condition, :ok ->
          case validate_condition(condition) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
    end
  end

  def validate(_other), do: {:error, "filter must be a map"}

  @doc """
  Compiles a filter into an Ecto query over visible profiles.
  """
  @spec to_query(map()) :: Ecto.Query.t()
  def to_query(filter) do
    base = from p in Profile, where: p.visibility == "directory"

    filter
    |> conditions()
    |> Enum.reduce(base, &apply_condition/2)
  end

  @doc """
  Renders a filter as the SQL it stands for.

  This is display only. It is never executed and never concatenated into a
  query; the executed form is `to_query/1`.
  """
  @spec to_sql(map()) :: binary()
  def to_sql(filter) do
    case conditions(filter) do
      [] ->
        "SELECT * FROM profiles"

      list ->
        predicates = Enum.map_join(list, "\n     AND ", &render_condition/1)
        "SELECT * FROM profiles\n   WHERE " <> predicates
    end
  end

  @doc """
  True when a profile satisfies a filter, evaluated in memory.

  Needed for the mutual-condition check, where both directions have to be
  tested for a pair at a time and issuing two queries per candidate would be
  wasteful.
  """
  @spec matches?(map() | Profile.t(), map()) :: boolean()
  def matches?(profile, filter) do
    values = profile_values(profile)
    Enum.all?(conditions(filter), &satisfied?(&1, values))
  end

  defp conditions(%{} = filter) do
    filter
    |> Map.get("all", Map.get(filter, :all, []))
    |> Enum.map(&normalize_condition/1)
  end

  defp conditions(_other), do: []

  defp normalize_condition(%{} = condition) do
    %{
      field: to_string(Map.get(condition, "field", Map.get(condition, :field, ""))),
      op: to_string(Map.get(condition, "op", Map.get(condition, :op, ""))),
      value: Map.get(condition, "value", Map.get(condition, :value))
    }
  end

  defp validate_condition(%{} = condition) do
    %{field: field, op: op, value: value} = normalize_condition(condition)

    cond do
      field not in @fields -> {:error, "#{field} は検索できない項目です"}
      field in @array_fields and op not in @array_ops -> {:error, "#{op} は配列項目に使えません"}
      field in @scalar_fields and op not in @scalar_ops -> {:error, "#{op} は使えない演算子です"}
      is_nil(value) -> {:error, "#{field} の値が空です"}
      op in ~w(any all_of in) and not is_list(value) -> {:error, "#{op} にはリストが必要です"}
      op in ~w(any all_of in) and length(value) > 20 -> {:error, "値は20件までです"}
      true -> :ok
    end
  end

  defp validate_condition(_other), do: {:error, "条件の形式が不正です"}

  defp apply_condition(%{field: field, op: op, value: value}, query) do
    column = String.to_existing_atom(field)

    case op do
      "eq" -> where(query, [p], field(p, ^column) == ^value)
      "neq" -> where(query, [p], field(p, ^column) != ^value)
      "gte" -> where(query, [p], field(p, ^column) >= ^value)
      "lte" -> where(query, [p], field(p, ^column) <= ^value)
      "in" -> where(query, [p], field(p, ^column) in ^value)
      "contains" -> where(query, [p], ^value in field(p, ^column))
      "any" -> where(query, [p], fragment("? && ?", field(p, ^column), ^value))
      "all_of" -> where(query, [p], fragment("? @> ?", field(p, ^column), ^value))
    end
  end

  defp render_condition(%{field: field, op: op, value: value}) do
    case op do
      "eq" -> "#{field} = #{literal(value)}"
      "neq" -> "#{field} <> #{literal(value)}"
      "gte" -> "#{field} >= #{literal(value)}"
      "lte" -> "#{field} <= #{literal(value)}"
      "in" -> "#{field} IN (#{Enum.map_join(value, ", ", &literal/1)})"
      "contains" -> "#{literal(value)} = ANY(#{field})"
      "any" -> "#{field} && #{array_literal(value)}"
      "all_of" -> "#{field} @> #{array_literal(value)}"
    end
  end

  defp literal(value) when is_binary(value), do: "'" <> String.replace(value, "'", "''") <> "'"
  defp literal(value) when is_boolean(value) or is_number(value), do: to_string(value)
  defp literal(value), do: inspect(value)

  defp array_literal(values), do: "ARRAY[" <> Enum.map_join(values, ", ", &literal/1) <> "]"

  defp profile_values(%Profile{} = profile) do
    Map.new(@fields, fn field ->
      {field, Map.get(profile, String.to_existing_atom(field))}
    end)
  end

  defp profile_values(%{} = map) do
    Map.new(@fields, fn field ->
      {field, Map.get(map, field, Map.get(map, String.to_existing_atom(field)))}
    end)
  end

  defp satisfied?(%{field: field, op: op, value: value}, values) do
    actual = Map.get(values, field)

    case {op, actual} do
      {_op, nil} -> false
      {"eq", actual} -> actual == value
      {"neq", actual} -> actual != value
      {"gte", actual} -> actual >= value
      {"lte", actual} -> actual <= value
      {"in", actual} -> actual in value
      {"contains", actual} when is_list(actual) -> value in actual
      {"any", actual} when is_list(actual) -> Enum.any?(value, &(&1 in actual))
      {"all_of", actual} when is_list(actual) -> Enum.all?(value, &(&1 in actual))
      _other -> false
    end
  end
end
