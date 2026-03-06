defmodule AttractorEx.Condition do
  @moduledoc false

  @operators ["==", "!=", ">=", "<=", ">", "<"]

  def evaluate(nil, _context), do: {:ok, true}

  def evaluate(expression, context) when is_binary(expression) and is_map(context) do
    expression
    |> String.split(~r/\s*&&\s*/, trim: true)
    |> Enum.reduce_while({:ok, true}, fn clause, _acc ->
      with {:ok, value} <- eval_clause(clause, context) do
        if value, do: {:cont, {:ok, true}}, else: {:halt, {:ok, false}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def valid?(expression) when is_binary(expression) do
    match?({:ok, _}, evaluate(expression, %{}))
  end

  defp eval_clause(clause, context) do
    trimmed = String.trim(clause)

    case parse_comparison(trimmed) do
      {:ok, {lhs, op, rhs}} ->
        lhs_value = resolve(lhs, context)
        rhs_value = parse_literal(rhs, context)
        {:ok, compare(lhs_value, op, rhs_value)}

      :no_match ->
        value = resolve(trimmed, context)
        {:ok, truthy?(value)}
    end
  end

  defp parse_comparison(clause) do
    op = Enum.find(@operators, &String.contains?(clause, &1))

    if is_nil(op) do
      :no_match
    else
      [lhs, rhs] = String.split(clause, op, parts: 2)
      {:ok, {String.trim(lhs), op, String.trim(rhs)}}
    end
  rescue
    _ -> :no_match
  end

  defp compare(lhs, "==", rhs), do: lhs == rhs
  defp compare(lhs, "!=", rhs), do: lhs != rhs
  defp compare(lhs, ">", rhs), do: to_number(lhs) > to_number(rhs)
  defp compare(lhs, "<", rhs), do: to_number(lhs) < to_number(rhs)
  defp compare(lhs, ">=", rhs), do: to_number(lhs) >= to_number(rhs)
  defp compare(lhs, "<=", rhs), do: to_number(lhs) <= to_number(rhs)

  defp parse_literal("\"" <> rest, _context), do: String.trim_trailing(rest, "\"")
  defp parse_literal("true", _context), do: true
  defp parse_literal("false", _context), do: false
  defp parse_literal("nil", _context), do: nil

  defp parse_literal(value, context) do
    cond do
      match?({_, ""}, Integer.parse(value)) ->
        {integer, ""} = Integer.parse(value)
        integer

      match?({_, ""}, Float.parse(value)) ->
        {float, ""} = Float.parse(value)
        float

      true ->
        resolve(value, context)
    end
  end

  defp resolve(path, context) do
    keys = String.split(path, ".", trim: true)

    Enum.reduce_while(keys, context, fn key, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, key) ->
          {:cont, Map.get(acc, key)}

        is_map(acc) and Map.has_key?(acc, String.to_atom(key)) ->
          {:cont, Map.get(acc, String.to_atom(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp to_number(value) when is_number(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> 0.0
    end
  end

  defp to_number(_), do: 0.0

  defp truthy?(value), do: value not in [false, nil, "", 0]
end
