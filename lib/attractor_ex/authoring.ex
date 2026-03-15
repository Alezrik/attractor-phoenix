defmodule AttractorEx.Authoring do
  @moduledoc """
  Canonical authoring helpers for DOT-backed builder workflows.

  This module keeps authoring fidelity aligned with the runtime by routing parsing,
  validation, formatting, templates, and autofix suggestions through the same
  normalized `AttractorEx.Graph` model used by execution.
  """

  alias AttractorEx.{Edge, Graph, Node, Parser, Validator}
  alias AttractorEx.HTTP.GraphRenderer

  @graph_attr_order ~w(
    goal
    label
    model_stylesheet
    default_max_retry
    default_fidelity
    retry_target
    fallback_retry_target
    stack.child_dotfile
  )

  @node_attr_order ~w(
    shape
    label
    type
    prompt
    tool_command
    class
    timeout
    max_retries
    goal_gate
    retry_target
    fallback_retry_target
    fidelity
    thread_id
    llm_provider
    llm_model
    reasoning_effort
    max_tokens
    temperature
    human.default_choice
    human.timeout
    human.input
    human.multiple
    human.required
    join_policy
    max_parallel
    k
    quorum_ratio
    manager.actions
    manager.max_cycles
    manager.poll_interval
    manager.stop_condition
    stack.child_autostart
    auto_status
    allow_partial
  )

  @edge_attr_order ~w(
    label
    status
    condition
    weight
    fidelity
    thread_id
    loop_restart
    tailport
    headport
  )

  @templates [
    %{
      id: "hello_world",
      name: "Hello World",
      description: "A minimal start-tool-exit workflow.",
      dot: """
      digraph attractor {
        graph [goal="Hello World", label="hello-world"]
        start [shape=Mdiamond, label="start"]
        hello [shape=parallelogram, label="hello", tool_command="echo hello world"]
        done [shape=Msquare, label="done"]

        start -> hello
        hello -> done
      }
      """
    },
    %{
      id: "approval_gate",
      name: "Approval Gate",
      description: "Ask a human before completing the workflow.",
      dot: """
      digraph attractor {
        graph [goal="Ship a release", label="approval-gate"]
        start [shape=Mdiamond, label="start"]
        review [shape=box, label="review", prompt="Summarize release risks"]
        gate [shape=hexagon, label="approve", prompt="Approve release?", human.timeout="30m"]
        done [shape=Msquare, label="done"]
        retry [shape=parallelogram, label="retry", tool_command="echo retry requested"]

        start -> review
        review -> gate
        gate -> done [label="[A] Approve"]
        gate -> retry [label="[R] Retry"]
        retry -> done
      }
      """
    },
    %{
      id: "parallel_review",
      name: "Parallel Review",
      description: "Run multiple review branches before converging.",
      dot: """
      digraph attractor {
        graph [goal="Review a change set", label="parallel-review"]
        start [shape=Mdiamond, label="start"]
        split [shape=component, label="split", join_policy="wait_all", max_parallel=2]
        code [shape=box, label="code", prompt="Review code quality"]
        docs [shape=box, label="docs", prompt="Review docs quality"]
        merge [shape=tripleoctagon, label="merge"]
        done [shape=Msquare, label="done"]

        start -> split
        split -> code
        split -> docs
        code -> merge
        docs -> merge
        merge -> done
      }
      """
    }
  ]

  @doc """
  Returns the canonical authoring analysis for a DOT document.
  """
  def analyze(dot) when is_binary(dot) do
    case Parser.parse(dot) do
      {:ok, graph} ->
        {:ok, response_for_graph(graph)}

      {:error, reason} ->
        {:error,
         %{
           "error" => reason,
           "diagnostics" => [parse_error_diagnostic(reason)],
           "autofixes" => [],
           "graph" => nil,
           "dot" => dot
         }}
    end
  end

  @doc """
  Returns the stable canonical DOT format for the given graph.
  """
  def format(%Graph{} = graph), do: format_graph(graph)

  def format(dot) when is_binary(dot) do
    with {:ok, graph} <- Parser.parse(dot) do
      {:ok, response_for_graph(graph)}
    end
  end

  @doc """
  Returns available builder templates.
  """
  def templates, do: @templates

  @doc """
  Applies a supported authoring transform and returns canonical output.
  """
  def transform(action, params \\ %{})

  def transform("apply_template", %{"template_id" => template_id}) do
    case Enum.find(@templates, &(&1.id == template_id)) do
      nil -> {:error, %{"error" => "unknown template", "template_id" => template_id}}
      template -> analyze(template.dot)
    end
  end

  def transform(action, %{"dot" => dot} = params) when is_binary(dot) do
    with {:ok, graph} <- Parser.parse(dot) do
      case apply_transform(graph, action, params) do
        {:ok, %Graph{} = next_graph} ->
          {:ok, response_for_graph(next_graph)}

        {:error, reason} ->
          {:error, %{"error" => reason}}
      end
    else
      {:error, reason} ->
        {:error,
         %{
           "error" => reason,
           "diagnostics" => [parse_error_diagnostic(reason)],
           "autofixes" => [],
           "graph" => nil,
           "dot" => dot
         }}
    end
  end

  def transform(_action, _params), do: {:error, %{"error" => "dot is required"}}

  defp response_for_graph(%Graph{} = graph) do
    diagnostics = Validator.validate(graph)
    %{"graph" => graph_json} = GraphRenderer.to_json(graph)

    %{
      "dot" => format_graph(graph),
      "graph" => graph_json,
      "diagnostics" => Enum.map(diagnostics, &normalize_diagnostic/1),
      "autofixes" => autofix_suggestions(graph, diagnostics)
    }
  end

  defp normalize_diagnostic(diag) do
    %{
      "severity" => Atom.to_string(diag.severity),
      "code" => to_string(diag.code),
      "rule" => diag.rule,
      "message" => diag.message,
      "node_id" => diag.node_id,
      "edge" => normalize_edge(diag.edge),
      "fix" => normalize_fix(diag.fix)
    }
  end

  defp normalize_edge({from, to}), do: %{"from" => from, "to" => to}
  defp normalize_edge(_edge), do: nil

  defp normalize_fix(nil), do: nil
  defp normalize_fix(value) when is_map(value), do: value
  defp normalize_fix(value), do: %{"value" => value}

  defp parse_error_diagnostic(reason) do
    %{
      "severity" => "error",
      "code" => "parse_error",
      "rule" => "parser",
      "message" => reason,
      "node_id" => nil,
      "edge" => nil,
      "fix" => nil
    }
  end

  defp autofix_suggestions(graph, diagnostics) do
    suggestions =
      []
      |> maybe_add_fix(missing_start?(diagnostics), %{
        "id" => "add_start_node",
        "label" => "Add Start Node",
        "description" => "Insert a canonical start node."
      })
      |> maybe_add_fix(missing_exit?(diagnostics), %{
        "id" => "add_exit_node",
        "label" => "Add Exit Node",
        "description" => "Insert a canonical terminal node."
      })
      |> maybe_add_fix(has_incoming_start_edges?(graph), %{
        "id" => "remove_start_incoming_edges",
        "label" => "Remove Start Incoming Edges",
        "description" => "Delete invalid edges that point into the start node."
      })
      |> maybe_add_fix(has_exit_outgoing_edges?(graph), %{
        "id" => "remove_exit_outgoing_edges",
        "label" => "Remove Exit Outgoing Edges",
        "description" => "Delete invalid edges that leave the exit node."
      })
      |> maybe_add_fix(connectable_dead_end_nodes(graph) != [], %{
        "id" => "connect_dead_ends_to_exit",
        "label" => "Connect Dead Ends To Exit",
        "description" => "Route dead-end nodes to the terminal node."
      })

    Enum.uniq_by(suggestions, & &1["id"])
  end

  defp maybe_add_fix(fixes, true, fix), do: [fix | fixes]
  defp maybe_add_fix(fixes, _condition, _fix), do: fixes

  defp missing_start?(diagnostics), do: Enum.any?(diagnostics, &(&1.code == :start_node))
  defp missing_exit?(diagnostics), do: Enum.any?(diagnostics, &(&1.code == :terminal_node))

  defp has_incoming_start_edges?(graph) do
    case Validator.start_node_id(graph) do
      nil -> false
      start_id -> Enum.any?(graph.edges, &(&1.to == start_id))
    end
  end

  defp has_exit_outgoing_edges?(graph) do
    exit_ids =
      graph.nodes
      |> Enum.filter(fn {_id, node} -> node.type == "exit" end)
      |> Enum.map(&elem(&1, 0))

    Enum.any?(graph.edges, &(&1.from in exit_ids))
  end

  defp connectable_dead_end_nodes(graph) do
    exit_id = first_exit_id(graph)

    if is_nil(exit_id) do
      []
    else
      graph.nodes
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(fn node ->
        node.type != "exit" and
          Enum.all?(graph.edges, &(&1.from != node.id)) and
          is_nil(node.retry_target) and
          is_nil(node.fallback_retry_target)
      end)
      |> Enum.map(& &1.id)
    end
  end

  defp apply_transform(graph, "format", _params), do: {:ok, graph}

  defp apply_transform(graph, "apply_fix", %{"fix_id" => fix_id}) do
    apply_fix(graph, fix_id)
  end

  defp apply_transform(_graph, action, _params),
    do: {:error, "unsupported transform action: #{action}"}

  defp apply_fix(graph, "add_start_node") do
    if Enum.any?(graph.nodes, fn {_id, node} -> node.type == "start" end) do
      {:ok, graph}
    else
      id = unique_node_id(graph, "start")
      start_node = Node.new(id, %{"shape" => "Mdiamond", "label" => id})
      {:ok, put_in(graph.nodes[id], start_node)}
    end
  end

  defp apply_fix(graph, "add_exit_node") do
    if Enum.any?(graph.nodes, fn {_id, node} -> node.type == "exit" end) do
      {:ok, graph}
    else
      id = unique_node_id(graph, "done")
      exit_node = Node.new(id, %{"shape" => "Msquare", "label" => id})
      {:ok, put_in(graph.nodes[id], exit_node)}
    end
  end

  defp apply_fix(graph, "remove_start_incoming_edges") do
    case Validator.start_node_id(graph) do
      nil -> {:ok, graph}
      start_id -> {:ok, %{graph | edges: Enum.reject(graph.edges, &(&1.to == start_id))}}
    end
  end

  defp apply_fix(graph, "remove_exit_outgoing_edges") do
    exit_ids =
      graph.nodes
      |> Enum.filter(fn {_id, node} -> node.type == "exit" end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    {:ok, %{graph | edges: Enum.reject(graph.edges, &MapSet.member?(exit_ids, &1.from))}}
  end

  defp apply_fix(graph, "connect_dead_ends_to_exit") do
    case first_exit_id(graph) do
      nil ->
        {:error, "cannot connect dead ends without an exit node"}

      exit_id ->
        next_edges =
          connectable_dead_end_nodes(graph)
          |> Enum.reduce(graph.edges, fn node_id, acc ->
            if Enum.any?(acc, &(&1.from == node_id and &1.to == exit_id)) do
              acc
            else
              acc ++ [Edge.new(node_id, exit_id, %{})]
            end
          end)

        {:ok, %{graph | edges: next_edges}}
    end
  end

  defp apply_fix(_graph, fix_id), do: {:error, "unsupported autofix: #{fix_id}"}

  defp first_exit_id(graph) do
    graph.nodes
    |> Enum.find_value(fn {id, node} -> if node.type == "exit", do: id, else: nil end)
  end

  defp unique_node_id(graph, base_id) do
    if Map.has_key?(graph.nodes, base_id) do
      1..1_000
      |> Enum.find_value(fn index ->
        candidate = "#{base_id}_#{index}"
        if Map.has_key?(graph.nodes, candidate), do: nil, else: candidate
      end)
    else
      base_id
    end
  end

  defp format_graph(%Graph{} = graph) do
    graph_id = serialize_identifier(graph.id)

    lines =
      [
        "digraph #{graph_id} {"
      ] ++
        maybe_attr_line("graph", graph.attrs, @graph_attr_order) ++
        maybe_attr_line("node", graph.node_defaults, @node_attr_order) ++
        maybe_attr_line("edge", graph.edge_defaults, @edge_attr_order) ++
        node_lines(graph) ++
        edge_lines(graph) ++
        ["}"]

    Enum.join(lines, "\n")
  end

  defp maybe_attr_line(_prefix, attrs, _order) when attrs == %{}, do: []

  defp maybe_attr_line(prefix, attrs, order) do
    case serialize_attrs(attrs, order) do
      "" -> []
      serialized -> ["  #{prefix} [#{serialized}]"]
    end
  end

  defp node_lines(%Graph{} = graph) do
    graph.nodes
    |> Enum.sort_by(fn {id, _node} -> id end)
    |> Enum.map(fn {id, node} ->
      attrs = canonical_node_attrs(node)
      "  #{serialize_identifier(id)} [#{serialize_attrs(attrs, @node_attr_order)}]"
    end)
  end

  defp edge_lines(%Graph{} = graph) do
    edges =
      graph.edges
      |> Enum.sort_by(fn edge ->
        {edge.from, edge.to, serialize_attrs(edge.attrs || %{}, @edge_attr_order)}
      end)

    if edges == [] do
      []
    else
      ["" | Enum.map(edges, &format_edge/1)]
    end
  end

  defp format_edge(edge) do
    case serialize_attrs(edge.attrs || %{}, @edge_attr_order) do
      "" ->
        "  #{serialize_identifier(edge.from)} -> #{serialize_identifier(edge.to)}"

      serialized ->
        "  #{serialize_identifier(edge.from)} -> #{serialize_identifier(edge.to)} [#{serialized}]"
    end
  end

  defp canonical_node_attrs(%Node{} = node) do
    attrs =
      node.attrs
      |> stringify_keys()
      |> Map.put("shape", node.shape)
      |> Map.put_new("label", node.id)

    implied_type = Node.handler_type_for_shape(node.shape)
    explicit_type = blank_to_nil(Map.get(attrs, "type"))

    cond do
      is_nil(explicit_type) ->
        attrs

      explicit_type == implied_type ->
        Map.delete(attrs, "type")

      true ->
        attrs
    end
  end

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp serialize_attrs(attrs, preferred_order) do
    attrs
    |> stringify_keys()
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.sort_by(fn {key, _value} ->
      case Enum.find_index(preferred_order, &(&1 == key)) do
        nil -> {1, key}
        index -> {0, index}
      end
    end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{serialize_attr_value(value)}" end)
  end

  defp serialize_attr_value(value) when is_boolean(value),
    do: if(value, do: "true", else: "false")

  defp serialize_attr_value(value) when is_integer(value), do: Integer.to_string(value)
  defp serialize_attr_value(value) when is_float(value), do: :erlang.float_to_binary(value)

  defp serialize_attr_value(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    ~s("#{escaped}")
  end

  defp serialize_identifier(value) do
    text = value |> to_string() |> String.trim()

    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_\-]*$/, text) do
      text
    else
      serialize_attr_value(text)
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
