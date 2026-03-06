defmodule AttractorEx.HandlerRegistryTest do
  use ExUnit.Case, async: false

  alias AttractorEx.{HandlerRegistry, Node}

  defmodule CustomHandler do
    def execute(_node, _context, _graph, _stage_dir, _opts), do: :ok
  end

  describe "spec: handler registry resolution order" do
    test "uses explicit node type when registered" do
      :ok = HandlerRegistry.register("custom.unit_test", CustomHandler)
      node = Node.new("n1", %{"shape" => "box", "type" => "custom.unit_test"})

      assert HandlerRegistry.resolve(node) == CustomHandler
      assert HandlerRegistry.handler_for(node) == CustomHandler
    end

    test "falls back to shape mapping when explicit type is missing or unknown" do
      node_with_unknown_type =
        Node.new("n1", %{"shape" => "parallelogram", "type" => "unknown.type"})

      node_with_blank_type = Node.new("n2", %{"shape" => "Mdiamond", "type" => " "})

      assert HandlerRegistry.resolve(node_with_unknown_type) == AttractorEx.Handlers.Tool
      assert HandlerRegistry.resolve(node_with_blank_type) == AttractorEx.Handlers.Start
    end

    test "uses codergen default when shape has no registered handler" do
      node = Node.new("n1", %{"shape" => "not_a_shape"})
      assert HandlerRegistry.resolve(node) == AttractorEx.Handlers.Codergen
    end
  end
end
