defmodule Mix.Tasks.Attractor.Http.Hello do
  use Mix.Task

  @shortdoc "Runs Noor Halden's schema-backed HTTP API hello world"

  @moduledoc """
  Runs Noor Halden's first schema-backed HTTP API hello world without folding it
  into the broader `mix test` or `mix attractor.http` loops.

      mix attractor.http.hello
      mix attractor.http.hello --trace
      mix attractor.http.hello qa/http_hello/http_hello_world_test.exs
  """

  @default_targets [
    "qa/http_hello/http_hello_world_test.exs",
    "qa/http_hello/attractor_http_hello_task_test.exs"
  ]
  @supported_switches [trace: :boolean, seed: :integer, max_cases: :integer]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @supported_switches)

    if invalid != [] do
      Mix.raise(
        "Unsupported options for mix attractor.http.hello: #{format_invalid_options(invalid)}"
      )
    end

    test_files = resolve_test_args(positional)

    Enum.each(test_files, fn path ->
      unless File.regular?(path) do
        Mix.raise("Hello-world test file not found: #{path}")
      end
    end)

    ex_unit!()
    |> apply(:start, [[autorun: false]])

    ex_unit!()
    |> apply(:configure, [ex_unit_configuration(opts)])

    Enum.each(test_files, &Code.require_file/1)

    %{failures: failures} =
      ex_unit!()
      |> apply(:run, [])

    if failures > 0 do
      Mix.raise("mix attractor.http.hello failed with #{failures} failing test(s).")
    end
  end

  @doc false
  def default_targets, do: @default_targets

  @doc false
  def resolve_test_args(args) do
    if explicit_test_target?(args) do
      args
    else
      args ++ @default_targets
    end
  end

  defp explicit_test_target?(args) do
    Enum.any?(args, fn arg ->
      String.starts_with?(arg, "test/") or
        String.starts_with?(arg, "test\\") or
        String.starts_with?(arg, "qa/") or
        String.starts_with?(arg, "qa\\") or
        String.ends_with?(arg, ".exs") or
        String.contains?(arg, ".exs:")
    end)
  end

  defp ex_unit_configuration(opts) do
    []
    |> maybe_put(:trace, Keyword.get(opts, :trace))
    |> maybe_put(:seed, Keyword.get(opts, :seed))
    |> maybe_put(:max_cases, Keyword.get(opts, :max_cases))
  end

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, key, value), do: Keyword.put(config, key, value)

  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map_join(", ", fn
      {option, nil} -> to_string(option)
      {option, value} -> "#{option}=#{value}"
    end)
  end

  defp ex_unit! do
    if Code.ensure_loaded?(ExUnit) do
      ExUnit
    else
      Mix.raise("ExUnit is unavailable in the current environment.")
    end
  end
end
