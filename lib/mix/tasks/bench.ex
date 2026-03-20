defmodule Mix.Tasks.Bench do
  use Mix.Task

  @shortdoc "Runs focused benchmark scripts from bench/"

  @moduledoc """
  Runs focused benchmark scripts from `bench/` without folding them into `mix test`.

      mix bench
      mix bench bench/my_benchmark.exs
      mix bench --script bench/my_benchmark.exs
  """

  @default_script Path.join("bench", "hello_world.exs")

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: [script: :string])

    if invalid != [] do
      Mix.raise("Unsupported options for mix bench: #{format_invalid_options(invalid)}")
    end

    script_path = resolve_script_path(positional, opts)

    unless File.regular?(script_path) do
      Mix.raise("Benchmark script not found: #{script_path}")
    end

    Code.require_file(script_path)
  end

  defp resolve_script_path([], opts) do
    opts
    |> Keyword.get(:script, @default_script)
    |> Path.expand(File.cwd!())
  end

  defp resolve_script_path([script_path], opts) do
    if Keyword.has_key?(opts, :script) do
      Mix.raise("Pass either a positional benchmark path or --script, not both.")
    end

    Path.expand(script_path, File.cwd!())
  end

  defp resolve_script_path(_paths, _opts) do
    Mix.raise("Expected at most one benchmark script path.")
  end

  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map_join(", ", fn
      {option, nil} -> to_string(option)
      {option, value} -> "#{option}=#{value}"
    end)
  end
end
