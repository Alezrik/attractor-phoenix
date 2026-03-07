defmodule AttractorExTest.ApplyGraphTransform do
  @moduledoc false

  def apply(graph) do
    task = Map.fetch!(graph.nodes, "task")

    patched_task = %{
      task
      | attrs: Map.put(task.attrs, "prompt", "apply transformed"),
        prompt: "apply transformed"
    }

    %{graph | nodes: Map.put(graph.nodes, "task", patched_task)}
  end
end
