defmodule Mix.Tasks.Coverage.Gate do
  use Mix.Task

  @shortdoc "Fails if the generated ExCoveralls report is below the configured minimum coverage"

  @moduledoc """
  Enforces the minimum coverage threshold configured in `coveralls.json`.

  This task expects `mix coveralls.json` to have been run already so that
  `cover/excoveralls.json` exists.
  """

  @impl Mix.Task
  def run(_args) do
    minimum = minimum_coverage!("coveralls.json")
    actual = actual_coverage!("cover/excoveralls.json")

    if actual + 1.0e-9 < minimum do
      Mix.raise(
        "Expected minimum coverage of #{format_percent(minimum)}%, got #{format_percent(actual)}%."
      )
    else
      Mix.shell().info(
        "Coverage gate passed: #{format_percent(actual)}% >= #{format_percent(minimum)}%."
      )
    end
  end

  defp minimum_coverage!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> get_in(["coverage_options", "minimum_coverage"])
    |> case do
      value when is_integer(value) -> value * 1.0
      value when is_float(value) -> value
      nil -> Mix.raise("Missing coverage_options.minimum_coverage in #{path}.")
      value -> Mix.raise("Invalid minimum_coverage in #{path}: #{inspect(value)}")
    end
  end

  defp actual_coverage!(path) do
    source_files =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.get("source_files")

    {covered, relevant} =
      Enum.reduce(source_files || [], {0, 0}, fn source_file, {covered_acc, relevant_acc} ->
        coverage = Map.get(source_file, "coverage", [])

        file_relevant = Enum.count(coverage, &(not is_nil(&1)))
        file_covered = Enum.count(coverage, &(is_integer(&1) and &1 > 0))

        {covered_acc + file_covered, relevant_acc + file_relevant}
      end)

    if relevant == 0 do
      Mix.raise("Coverage report at #{path} does not contain any relevant lines.")
    else
      covered * 100.0 / relevant
    end
  end

  defp format_percent(value) do
    value
    |> Float.round(1)
    |> :erlang.float_to_binary(decimals: 1)
  end
end
