defmodule AttractorEx do
  @moduledoc """
  Elixir implementation of the Attractor pipeline engine.
  """

  alias AttractorEx.Engine

  @spec run(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, %{diagnostics: list()}} | {:error, %{error: String.t()}}
  def run(dot, context \\ %{}, opts \\ []) when is_binary(dot) and is_map(context) do
    Engine.run(dot, context, opts)
  end
end
