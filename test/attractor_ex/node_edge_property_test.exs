defmodule AttractorEx.NodeEdgePropertyTest do
  use ExUnit.Case, async: true
  use PropCheck, default_opts: [numtests: 100]

  import AttractorEx.TestGenerators

  alias AttractorEx.{Edge, Node}

  property "canonical shapes map consistently between handler lookup and node construction" do
    forall shape <- canonical_shape() do
      node = Node.new("task", %{"shape" => shape})
      node.type == Node.handler_type_for_shape(shape)
    end
  end

  property "explicit node type overrides shape-derived type" do
    forall [shape, explicit_type] <- [canonical_shape(), nonempty_identifier()] do
      Node.new("task", %{"shape" => shape, "type" => explicit_type}).type == explicit_type
    end
  end

  property "goal_gate accepts the supported truthy string forms" do
    forall raw <- elements([true, "true", " TRUE ", "1", " yes "]) do
      Node.new("task", %{"goal_gate" => raw}).goal_gate == true
    end
  end

  property "retry targets are trimmed and blank values collapse to nil" do
    forall [target, left_ws, right_ws] <- [
             nonempty_identifier(),
             list(elements([" ", "\t"])),
             list(elements([" ", "\t"]))
           ] do
      padded = Enum.join(left_ws, "") <> target <> Enum.join(right_ws, "")
      blank = Enum.join(left_ws ++ right_ws, "")

      node =
        Node.new("task", %{
          "retry_target" => padded,
          "fallback_retry_target" => blank
        })

      node.retry_target == target and is_nil(node.fallback_retry_target)
    end
  end

  property "edge status falls back to outcome when explicit status is absent" do
    forall outcome <- nonempty_identifier() do
      Edge.new("a", "b", %{"outcome" => outcome}).status == outcome
    end
  end

  property "edge condition and status are trimmed and blank values collapse to nil" do
    forall [condition, status, left_ws, right_ws] <- [
             nonempty_identifier(),
             nonempty_identifier(),
             list(elements([" ", "\t"])),
             list(elements([" ", "\t"]))
           ] do
      padded_condition = Enum.join(left_ws, "") <> condition <> Enum.join(right_ws, "")
      padded_status = Enum.join(right_ws, "") <> status <> Enum.join(left_ws, "")
      blank = Enum.join(left_ws ++ right_ws, "")
      edge = Edge.new("a", "b", %{"condition" => padded_condition, "status" => padded_status})
      blank_edge = Edge.new("a", "b", %{"condition" => blank, "status" => blank})

      edge.condition == condition and edge.status == status and
        is_nil(blank_edge.condition) and is_nil(blank_edge.status)
    end
  end
end
