defmodule AttractorEx.Agent.LocalExecutionEnvironment do
  @moduledoc """
  Local filesystem-backed execution environment for agent sessions.

  It exposes a working directory, platform information, and the built-in
  filesystem/shell primitives used by the coding-agent loop.
  """

  @behaviour AttractorEx.Agent.ExecutionEnvironment

  defstruct working_dir: nil, env: %{}

  @type t :: %__MODULE__{
          working_dir: String.t() | nil,
          env: %{optional(String.t()) => String.t()}
        }

  @spec new(keyword()) :: t()
  @doc "Builds a local execution environment."
  def new(opts \\ []) do
    %__MODULE__{
      working_dir: Keyword.get(opts, :working_dir),
      env: Keyword.get(opts, :env, %{})
    }
  end

  @impl true
  def working_directory(%__MODULE__{working_dir: nil}) do
    File.cwd!()
  end

  def working_directory(%__MODULE__{working_dir: path}) do
    path
  end

  @impl true
  def platform(_env) do
    os = :os.type()
    "#{elem(os, 0)}-#{elem(os, 1)}"
  end

  @impl true
  def read_file(%__MODULE__{} = env, path) when is_binary(path) do
    env
    |> resolve_path(path)
    |> File.read()
  end

  @impl true
  def write_file(%__MODULE__{} = env, path, content)
      when is_binary(path) and is_binary(content) do
    resolved = resolve_path(env, path)

    :ok = File.mkdir_p(Path.dirname(resolved))
    File.write(resolved, content)
  end

  @impl true
  def list_directory(%__MODULE__{} = env, path \\ ".") when is_binary(path) do
    resolved = resolve_path(env, path)

    with {:ok, entries} <- File.ls(resolved) do
      items =
        entries
        |> Enum.sort()
        |> Enum.map(fn entry ->
          full_path = Path.join(resolved, entry)

          %{
            name: entry,
            path: relative_to_root(env, full_path),
            type: entry_type(full_path)
          }
        end)

      {:ok, items}
    end
  end

  @impl true
  def glob(%__MODULE__{} = env, pattern) when is_binary(pattern) do
    root = working_directory(env)

    matches =
      pattern
      |> Path.expand(root)
      |> Path.wildcard(match_dot: true)
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.sort()

    {:ok, matches}
  end

  @impl true
  def grep(%__MODULE__{} = env, pattern, opts \\ []) when is_binary(pattern) do
    search_root = Keyword.get(opts, :path, ".")
    max_results = Keyword.get(opts, :max_results, 200)
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    path = resolve_path(env, search_root)

    if rg = System.find_executable("rg") do
      run_rg(rg, env, path, pattern, max_results, case_sensitive)
    else
      grep_with_elixir(env, path, pattern, max_results, case_sensitive)
    end
  end

  @impl true
  def shell_command(%__MODULE__{} = env, command, opts \\ []) when is_binary(command) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 10_000)
    max_output_bytes = Keyword.get(opts, :max_output_bytes, 64_000)
    {shell, shell_flag} = shell(env)

    cmd_opts = [
      cd: working_directory(env),
      stderr_to_stdout: true,
      into: "",
      env: shell_env(env)
    ]

    task =
      Task.async(fn ->
        System.cmd(shell, [shell_flag, command], cmd_opts)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        truncated? = byte_size(output) > max_output_bytes

        bounded_output =
          if truncated? do
            binary_part(output, 0, max_output_bytes) <>
              "\n[WARNING: shell output truncated by execution environment]"
          else
            output
          end

        {:ok, %{output: bounded_output, exit_code: exit_code, truncated?: truncated?}}

      nil ->
        {:error, :timeout}
    end
  end

  @impl true
  def environment_context(%__MODULE__{} = env) do
    %{
      working_directory: working_directory(env),
      platform: platform(env),
      available_env_vars: env.env |> Map.keys() |> Enum.sort()
    }
  end

  defp resolve_path(%__MODULE__{} = env, path) do
    root = working_directory(env)

    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, root)
    end
  end

  defp relative_to_root(%__MODULE__{} = env, path) do
    Path.relative_to(path, working_directory(env))
  end

  defp entry_type(path) do
    cond do
      File.dir?(path) -> "directory"
      File.regular?(path) -> "file"
      true -> "other"
    end
  end

  defp shell(_env) do
    case :os.type() do
      {:win32, _} -> {"powershell", "-Command"}
      _ -> {"sh", "-lc"}
    end
  end

  defp shell_env(%__MODULE__{env: env}) do
    Map.to_list(env)
  end

  defp run_rg(rg, env, path, pattern, max_results, case_sensitive) do
    args =
      [
        "--json",
        "--line-number",
        "--with-filename",
        "--max-count",
        Integer.to_string(max_results)
      ] ++
        if(case_sensitive, do: [], else: ["-i"]) ++
        [pattern, path]

    case System.cmd(rg, args, cd: working_directory(env), stderr_to_stdout: true, into: "") do
      {output, exit_code} when exit_code in [0, 1] ->
        matches =
          output
          |> String.split("\n", trim: true)
          |> Enum.flat_map(&decode_rg_match(&1, env))
          |> Enum.take(max_results)

        {:ok, matches}

      {_output, exit_code} ->
        {:error, {:rg_failed, exit_code}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp decode_rg_match(line, env) do
    case Jason.decode(line) do
      {:ok, %{"type" => "match", "data" => data}} ->
        [
          %{
            path: relative_to_root(env, get_in(data, ["path", "text"]) || ""),
            line_number: data["line_number"],
            line: get_in(data, ["lines", "text"]) |> to_string() |> String.trim_trailing()
          }
        ]

      _ ->
        []
    end
  end

  defp grep_with_elixir(env, path, pattern, max_results, case_sensitive) do
    matcher =
      if case_sensitive do
        fn line -> String.contains?(line, pattern) end
      else
        lowered = String.downcase(pattern)
        fn line -> String.contains?(String.downcase(line), lowered) end
      end

    matches =
      path
      |> collect_files()
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, content} ->
            content
            |> String.split("\n")
            |> Enum.with_index(1)
            |> Enum.flat_map(fn {line, line_number} ->
              if matcher.(line) do
                [
                  %{
                    path: relative_to_root(env, file),
                    line_number: line_number,
                    line: line
                  }
                ]
              else
                []
              end
            end)

          {:error, _reason} ->
            []
        end
      end)
      |> Enum.take(max_results)

    {:ok, matches}
  end

  defp collect_files(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        Path.wildcard(Path.join(path, "**/*"), match_dot: true) |> Enum.filter(&File.regular?/1)

      true ->
        []
    end
  end
end
