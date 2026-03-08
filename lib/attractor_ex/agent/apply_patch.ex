defmodule AttractorEx.Agent.ApplyPatch do
  @moduledoc """
  Applies `apply_patch` v4a-style filesystem updates against a local execution environment.

  The implementation is intentionally conservative. It supports add, delete, update,
  and move operations using the appendix-style patch envelope and verifies update hunks
  against current file contents before writing changes.
  """

  alias AttractorEx.Agent.ExecutionEnvironment

  @type operation_result :: %{operation: String.t(), path: String.t()}

  @spec apply(term(), String.t()) :: {:ok, [operation_result()]} | {:error, String.t()}
  def apply(env, patch) when is_binary(patch) do
    with :ok <- ensure_local_environment(env),
         {:ok, operations} <- parse_patch(patch) do
      apply_operations(env, operations)
    end
  end

  defp ensure_local_environment(env) do
    if ExecutionEnvironment.implementation?(env) and
         match?(%AttractorEx.Agent.LocalExecutionEnvironment{}, env) do
      :ok
    else
      {:error, "apply_patch requires LocalExecutionEnvironment"}
    end
  end

  defp parse_patch(patch) do
    lines =
      patch
      |> String.split("\n", trim: false)
      |> drop_trailing_empty_lines()

    with :ok <- expect_begin(lines),
         :ok <- expect_end(lines) do
      lines
      |> Enum.drop(1)
      |> Enum.drop(-1)
      |> parse_operations([])
    end
  end

  defp expect_begin(["*** Begin Patch" | _rest]), do: :ok
  defp expect_begin(_lines), do: {:error, "patch must start with *** Begin Patch"}

  defp expect_end(lines) do
    if List.last(lines) == "*** End Patch" do
      :ok
    else
      {:error, "patch must end with *** End Patch"}
    end
  end

  defp parse_operations([], acc), do: {:ok, Enum.reverse(acc)}
  defp parse_operations(["" | rest], acc), do: parse_operations(rest, acc)

  defp parse_operations(["*** Add File: " <> path | rest], acc) do
    {content_lines, remaining} = Enum.split_while(rest, &(not operation_header?(&1)))

    case content_lines do
      [] ->
        {:error, "add file operation requires at least one + line for #{path}"}

      lines ->
        with {:ok, content} <- parse_add_lines(path, lines) do
          parse_operations(remaining, [%{type: :add, path: path, content: content} | acc])
        end
    end
  end

  defp parse_operations(["*** Delete File: " <> path | rest], acc) do
    parse_operations(rest, [%{type: :delete, path: path} | acc])
  end

  defp parse_operations(["*** Update File: " <> path | rest], acc) do
    {move_to, rest} = parse_move(rest)
    {change_lines, remaining} = Enum.split_while(rest, &(not operation_header?(&1)))

    if change_lines == [] do
      {:error, "update file operation requires hunks for #{path}"}
    else
      parse_operations(
        remaining,
        [%{type: :update, path: path, move_to: move_to, changes: change_lines} | acc]
      )
    end
  end

  defp parse_operations([line | _rest], _acc) do
    {:error, "unrecognized patch line: #{inspect(line)}"}
  end

  defp parse_move(["*** Move to: " <> path | rest]), do: {path, rest}
  defp parse_move(rest), do: {nil, rest}

  defp parse_add_lines(path, lines) do
    Enum.reduce_while(lines, {:ok, []}, fn
      "+" <> content, {:ok, acc} ->
        {:cont, {:ok, [content | acc]}}

      line, _acc ->
        {:halt, {:error, "invalid add line for #{path}: #{inspect(line)}"}}
    end)
    |> case do
      {:ok, content_lines} -> {:ok, Enum.reverse(content_lines) |> Enum.join("\n")}
      error -> error
    end
  end

  defp operation_header?(""), do: false
  defp operation_header?("*** End Patch"), do: true
  defp operation_header?("*** Add File: " <> _path), do: true
  defp operation_header?("*** Delete File: " <> _path), do: true
  defp operation_header?("*** Update File: " <> _path), do: true
  defp operation_header?(_line), do: false

  defp drop_trailing_empty_lines(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp apply_operations(env, operations) do
    Enum.reduce_while(operations, {:ok, []}, fn operation, {:ok, acc} ->
      case apply_operation(env, operation) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp apply_operation(env, %{type: :add, path: path, content: content}) do
    case ExecutionEnvironment.write_file(env, path, content) do
      :ok -> {:ok, %{operation: "add", path: path}}
      {:error, reason} -> {:error, "failed to add #{path}: #{inspect(reason)}"}
    end
  end

  defp apply_operation(env, %{type: :delete, path: path}) do
    case File.rm(resolve_path(env, path)) do
      :ok -> {:ok, %{operation: "delete", path: path}}
      {:error, reason} -> {:error, "failed to delete #{path}: #{inspect(reason)}"}
    end
  end

  defp apply_operation(env, %{type: :update, path: path, move_to: move_to, changes: changes}) do
    with {:ok, original} <- read_existing_file(env, path),
         {:ok, updated} <- apply_changes(original, changes),
         :ok <- write_updated_file(env, path, updated) do
      maybe_move_file(env, path, move_to)
    end
  end

  defp read_existing_file(env, path) do
    case ExecutionEnvironment.read_file(env, path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "failed to read #{path}: #{inspect(reason)}"}
    end
  end

  defp write_updated_file(env, path, content) do
    case ExecutionEnvironment.write_file(env, path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "failed to write #{path}: #{inspect(reason)}"}
    end
  end

  defp maybe_move_file(_env, path, nil), do: {:ok, %{operation: "update", path: path}}

  defp maybe_move_file(env, path, move_to) do
    source = resolve_path(env, path)
    destination = resolve_path(env, move_to)

    with :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- File.rename(source, destination) do
      {:ok, %{operation: "update+move", path: move_to}}
    else
      {:error, reason} -> {:error, "failed to move #{path} to #{move_to}: #{inspect(reason)}"}
    end
  end

  defp apply_changes(original, change_lines) do
    with {:ok, hunks} <- build_hunks(change_lines, []),
         {:ok, updated_lines} <- apply_hunks(String.split(original, "\n", trim: false), hunks) do
      {:ok, join_lines(updated_lines, String.ends_with?(original, "\n"))}
    end
  end

  defp build_hunks([], acc), do: {:ok, Enum.reverse(acc)}

  defp build_hunks(["@@" <> _marker | rest], acc) do
    {hunk_lines, remaining} =
      Enum.split_while(rest, fn line ->
        not String.starts_with?(line, "@@") and line != "*** End of File"
      end)

    build_hunks(remaining, [hunk_lines | acc])
  end

  defp build_hunks(["*** End of File" | rest], acc), do: build_hunks(rest, acc)

  defp build_hunks([line | _rest], _acc) do
    {:error, "invalid update hunk line: #{inspect(line)}"}
  end

  defp apply_hunks(original_lines, hunks) do
    Enum.reduce_while(hunks, {:ok, {original_lines, [], 0}}, fn hunk,
                                                                {:ok, {source, acc, cursor}} ->
      case apply_hunk(source, hunk, acc, cursor) do
        {:ok, next_source, next_acc, next_cursor} ->
          {:cont, {:ok, {next_source, next_acc, next_cursor}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {source, acc, _cursor}} -> {:ok, acc ++ source}
      error -> error
    end
  end

  defp apply_hunk(source, hunk, acc, cursor) do
    anchor =
      Enum.find_value(hunk, fn
        " " <> text -> text
        "-" <> text -> text
        _line -> nil
      end)

    with {:ok, source, acc, cursor} <- seek_anchor(source, acc, cursor, anchor) do
      consume_hunk_lines(source, hunk, acc, cursor)
    end
  end

  defp seek_anchor(source, acc, cursor, nil), do: {:ok, source, acc, cursor}

  defp seek_anchor(source, acc, cursor, anchor) do
    case Enum.split_while(source, &(&1 != anchor)) do
      {skipped, [_match | _rest] = remaining} ->
        {:ok, remaining, acc ++ skipped, cursor + length(skipped)}

      {_skipped, []} ->
        {:error, "failed to locate patch anchor #{inspect(anchor)}"}
    end
  end

  defp consume_hunk_lines(source, [], acc, cursor), do: {:ok, source, acc, cursor}

  defp consume_hunk_lines(source, [" " <> text | rest], acc, cursor) do
    case source do
      [^text | remaining] ->
        consume_hunk_lines(remaining, rest, acc ++ [text], cursor + 1)

      [actual | _remaining] ->
        {:error,
         "context mismatch at source line #{cursor + 1}: expected #{inspect(text)}, got #{inspect(actual)}"}

      [] ->
        {:error, "context mismatch at end of file"}
    end
  end

  defp consume_hunk_lines(source, ["-" <> text | rest], acc, cursor) do
    case source do
      [^text | remaining] ->
        consume_hunk_lines(remaining, rest, acc, cursor + 1)

      [actual | _remaining] ->
        {:error,
         "delete mismatch at source line #{cursor + 1}: expected #{inspect(text)}, got #{inspect(actual)}"}

      [] ->
        {:error, "delete mismatch at end of file"}
    end
  end

  defp consume_hunk_lines(source, ["+" <> text | rest], acc, cursor) do
    consume_hunk_lines(source, rest, acc ++ [text], cursor)
  end

  defp consume_hunk_lines(_source, [line | _rest], _acc, _cursor) do
    {:error, "invalid patch operation line: #{inspect(line)}"}
  end

  defp join_lines(lines, true), do: Enum.join(lines, "\n")

  defp join_lines(lines, false) do
    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n")
    end
  end

  defp resolve_path(env, path) do
    working_dir = ExecutionEnvironment.working_directory(env)

    if Path.type(path) == :absolute do
      Path.expand(path)
    else
      Path.expand(path, working_dir)
    end
  end
end
