defmodule AttractorEx.Agent.ToolRegistry do
  @moduledoc """
  Lightweight registry of agent tools keyed by name.
  """

  alias AttractorEx.Agent.Tool

  @type t :: %{optional(String.t()) => Tool.t()}

  @spec from_tools([Tool.t()]) :: t()
  @doc "Builds a registry map from a tool list."
  def from_tools(tools) do
    tools
    |> Enum.map(fn %Tool{name: name} = tool -> {name, tool} end)
    |> Map.new()
  end

  @spec get(t(), String.t()) :: Tool.t() | nil
  @doc "Fetches a tool by name."
  def get(registry, name) when is_map(registry) and is_binary(name) do
    Map.get(registry, name)
  end

  @spec register(t(), Tool.t()) :: t()
  @doc "Registers or replaces a tool in the registry."
  def register(registry, %Tool{name: name} = tool) do
    Map.put(registry, name, tool)
  end
end
