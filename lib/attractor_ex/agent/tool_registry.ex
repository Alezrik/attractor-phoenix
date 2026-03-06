defmodule AttractorEx.Agent.ToolRegistry do
  @moduledoc false

  alias AttractorEx.Agent.Tool

  @type t :: %{optional(String.t()) => Tool.t()}

  @spec from_tools([Tool.t()]) :: t()
  def from_tools(tools) do
    tools
    |> Enum.map(fn %Tool{name: name} = tool -> {name, tool} end)
    |> Map.new()
  end

  @spec get(t(), String.t()) :: Tool.t() | nil
  def get(registry, name) when is_map(registry) and is_binary(name) do
    Map.get(registry, name)
  end

  @spec register(t(), Tool.t()) :: t()
  def register(registry, %Tool{name: name} = tool) do
    Map.put(registry, name, tool)
  end
end
