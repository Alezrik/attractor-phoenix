defmodule AttractorEx.Transforms.VariableExpansion do
  @moduledoc """
  Built-in graph transform that expands simple runtime variables such as `$goal`.
  """

  alias AttractorEx.{Edge, Graph, Node}

  def transform(%Graph{} = graph) do
    substitutions = %{"goal" => Map.get(graph.attrs, "goal", "")}

    %Graph{
      graph
      | attrs: expand_attrs(graph.attrs, substitutions),
        nodes: expand_nodes(graph.nodes, substitutions),
        edges: expand_edges(graph.edges, substitutions)
    }
  end

  defp expand_nodes(nodes, substitutions) do
    nodes
    |> Enum.map(fn {id, node} ->
      attrs = expand_attrs(node.attrs, substitutions)
      {id, Node.new(id, attrs)}
    end)
    |> Map.new()
  end

  defp expand_edges(edges, substitutions) do
    Enum.map(edges, fn edge ->
      edge.attrs
      |> expand_attrs(substitutions)
      |> then(&Edge.new(edge.from, edge.to, &1))
    end)
  end

  defp expand_attrs(attrs, substitutions) do
    attrs
    |> Enum.map(fn {key, value} -> {key, expand_value(value, substitutions)} end)
    |> Map.new()
  end

  defp expand_value(value, substitutions) when is_binary(value) do
    Enum.reduce(substitutions, value, fn {key, replacement}, acc ->
      String.replace(acc, "$#{key}", to_string(replacement || ""))
    end)
  end

  defp expand_value(value, _substitutions), do: value
end
