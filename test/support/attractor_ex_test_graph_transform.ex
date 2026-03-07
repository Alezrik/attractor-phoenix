defmodule AttractorExTest.GraphTransform do
  @moduledoc false

  def transform(graph) do
    task = Map.fetch!(graph.nodes, "task")

    patched_task = %{
      task
      | attrs: Map.put(task.attrs, "prompt", "module transformed"),
        prompt: "module transformed"
    }

    %{graph | nodes: Map.put(graph.nodes, "task", patched_task)}
  end
end
