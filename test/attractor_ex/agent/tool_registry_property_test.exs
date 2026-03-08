defmodule AttractorEx.Agent.ToolRegistryPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck, default_opts: [numtests: 100]

  import AttractorEx.TestGenerators

  alias AttractorEx.Agent.{Tool, ToolRegistry}

  property "from_tools builds a registry that can fetch each uniquely named tool" do
    forall [name_a, name_b] <- [nonempty_identifier(), nonempty_identifier()] do
      name_b = if name_a == name_b, do: name_b <> "_b", else: name_b

      tool_a = %Tool{name: name_a, description: "A", parameters: %{}, execute: fn _, _ -> :ok end}
      tool_b = %Tool{name: name_b, description: "B", parameters: %{}, execute: fn _, _ -> :ok end}
      registry = ToolRegistry.from_tools([tool_a, tool_b])

      ToolRegistry.get(registry, name_a) == tool_a and
        ToolRegistry.get(registry, name_b) == tool_b
    end
  end

  property "register replaces an existing tool with the same name" do
    forall name <- nonempty_identifier() do
      original = %Tool{
        name: name,
        description: "old",
        parameters: %{},
        execute: fn _, _ -> :old end
      }

      replacement = %Tool{
        name: name,
        description: "new",
        parameters: %{},
        execute: fn _, _ -> :new end
      }

      registry =
        [original]
        |> ToolRegistry.from_tools()
        |> ToolRegistry.register(replacement)

      ToolRegistry.get(registry, name) == replacement
    end
  end

  property "tool definitions expose only model-facing fields" do
    forall [name, description] <- [nonempty_identifier(), identifier()] do
      tool = %Tool{
        name: name,
        description: description,
        parameters: %{"type" => "object"},
        execute: fn _, _ -> :ok end,
        target: :session
      }

      Tool.definition(tool) == %{
        name: name,
        description: description,
        parameters: %{"type" => "object"}
      }
    end
  end
end
