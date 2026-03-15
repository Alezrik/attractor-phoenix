defmodule AttractorExTest.ConformanceFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias AttractorEx.Agent.{
    LocalExecutionEnvironment,
    ProviderProfile,
    Session,
    Tool,
    ToolRegistry
  }

  alias AttractorEx.LLM.Client

  def parsing_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      plan [shape=box, prompt="Plan feature"]
      done [shape=Msquare]
      start -> plan -> done
    }
    """
  end

  def invalid_dot, do: "graph not-a-digraph { start -- done }"

  def runtime_dot do
    """
    digraph attractor {
      graph [goal="Ship release"]
      start [shape=Mdiamond]
      plan [shape=box, prompt="Plan for $goal"]
      implement [shape=box, prompt="Implement"]
      done [shape=Msquare]
      start -> plan -> implement -> done
    }
    """
  end

  def transport_dot do
    """
    digraph attractor {
      graph [goal="Ship feature"]
      start [shape=Mdiamond]
      plan [shape=box, prompt="Plan for $goal"]
      done [shape=Msquare]
      start -> plan -> done
    }
    """
  end

  def human_gate_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      gate [shape=hexagon, prompt="Approve release?", human.timeout="5s"]
      done [shape=Msquare]
      retry [shape=box, prompt="Retry release"]
      start -> gate
      gate -> done [label="[A] Approve"]
      gate -> retry [label="[R] Retry"]
      retry -> done
    }
    """
  end

  def unique_logs_root(tag) do
    Path.join(
      System.tmp_dir!(),
      "attractor_conformance_#{tag}_#{System.unique_integer([:positive])}"
    )
  end

  def unique_store_root(tag) do
    Path.join(
      System.tmp_dir!(),
      "attractor_conformance_store_#{tag}_#{System.unique_integer([:positive])}"
    )
  end

  def wait_until(fun, attempts \\ 80)

  def wait_until(_fun, 0), do: flunk("condition was not met in time")

  def wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      receive do
      after
        10 -> wait_until(fun, attempts - 1)
      end
    end
  end

  def build_agent_session(scenario) do
    tool = %Tool{
      name: "echo",
      description: "echo input text",
      parameters: %{},
      execute: fn args, _env -> args["text"] || "" end
    }

    tools = [tool]

    profile =
      ProviderProfile.openai(model: "gpt-5.2")
      |> then(fn profile ->
        %{
          profile
          | tools: tools,
            tool_registry: ToolRegistry.from_tools(tools),
            provider_options: %{"scenario" => scenario}
        }
      end)

    client = %Client{providers: %{"openai" => AttractorExTest.AgentAdapter}}

    Session.new(client, profile,
      execution_env: LocalExecutionEnvironment.new(working_dir: File.cwd!())
    )
  end
end
