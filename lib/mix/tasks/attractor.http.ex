defmodule Mix.Tasks.Attractor.Http do
  use Mix.Task

  @shortdoc "Runs the focused AttractorEx HTTP API suite"

  @moduledoc """
  Runs the focused AttractorEx HTTP API suite without folding it into the full
  `mix test` loop.

      mix attractor.http
      mix attractor.http --trace
      mix attractor.http test/attractor_ex/http_test.exs
  """

  @default_targets [
    "test/attractor_ex/http_manager_test.exs",
    "test/attractor_ex/http_test.exs",
    "test/attractor_ex/conformance/transport_conformance_test.exs"
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.reenable("test")
    Mix.Tasks.Test.run(resolve_test_args(args))
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
        String.ends_with?(arg, ".exs") or
        String.contains?(arg, ".exs:")
    end)
  end
end
