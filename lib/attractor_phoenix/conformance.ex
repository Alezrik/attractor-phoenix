defmodule AttractorPhoenix.Conformance do
  @moduledoc """
  Maintained black-box conformance scoreboard for the public proof surface.

  The scoreboard is intentionally documentation-friendly: each suite exposes its
  domain, current score, executable evidence target, and any remaining published gaps.
  """

  @suite_scores %{
    parsing: 4.5,
    runtime: 4.0,
    state: 3.5,
    transport: 4.0,
    agent_loop: 4.0,
    unified_llm: 4.0
  }

  @suites [
    %{
      id: :parsing,
      label: "Parsing",
      description: "Public DOT parsing and validation contracts.",
      scenarios: [
        %{
          id: "parse-valid-dot",
          title: "Accepts the supported DOT subset through the public parser surface.",
          status: :implemented
        },
        %{
          id: "reject-invalid-dot",
          title: "Rejects malformed non-digraph input with an explicit parse error.",
          status: :implemented
        }
      ],
      evidence: [
        %{label: "Suite", path: "test/attractor_ex/conformance/parsing_conformance_test.exs"},
        %{
          label: "Command",
          command: "mix test test/attractor_ex/conformance/parsing_conformance_test.exs"
        }
      ]
    },
    %{
      id: :runtime,
      label: "Runtime",
      description: "Black-box execution, artifacts, and resume semantics.",
      scenarios: [
        %{
          id: "run-pipeline",
          title: "Executes a pipeline and emits the expected run artifacts.",
          status: :implemented
        },
        %{
          id: "resume-checkpoint",
          title: "Resumes a pipeline from checkpoint.json using the public API.",
          status: :implemented
        }
      ],
      evidence: [
        %{label: "Suite", path: "test/attractor_ex/conformance/runtime_conformance_test.exs"},
        %{
          label: "Command",
          command: "mix test test/attractor_ex/conformance/runtime_conformance_test.exs"
        }
      ]
    },
    %{
      id: :state,
      label: "State",
      description: "Durable HTTP-manager run state, checkpoint, and replay evidence.",
      scenarios: [
        %{
          id: "persist-run-record",
          title: "Persists run status, context, and events across manager restart.",
          status: :implemented
        },
        %{
          id: "recover-incomplete-run",
          title: "Recovers durable state through the file-backed run store contract.",
          status: :partial
        }
      ],
      evidence: [
        %{label: "Suite", path: "test/attractor_ex/conformance/state_conformance_test.exs"},
        %{
          label: "Command",
          command: "mix test test/attractor_ex/conformance/state_conformance_test.exs"
        }
      ]
    },
    %{
      id: :transport,
      label: "Transport",
      description: "Public HTTP creation, status, question, and answer semantics.",
      scenarios: [
        %{
          id: "create-and-status",
          title: "Creates a pipeline over HTTP and exposes status plus context endpoints.",
          status: :implemented
        },
        %{
          id: "human-answer-flow",
          title: "Accepts wait.human answers over the HTTP answer surface.",
          status: :implemented
        }
      ],
      evidence: [
        %{label: "Suite", path: "test/attractor_ex/conformance/transport_conformance_test.exs"},
        %{
          label: "Command",
          command: "mix test test/attractor_ex/conformance/transport_conformance_test.exs"
        }
      ]
    },
    %{
      id: :agent_loop,
      label: "Agent Loop",
      description: "Session-level tool execution and provider-preset behavior.",
      scenarios: [
        %{
          id: "provider-preset-tool-round",
          title: "Provider presets execute a tool round and emit the maintained event surface.",
          status: :implemented
        },
        %{
          id: "instruction-layering",
          title: "Project instruction files are layered into the session prompt context.",
          status: :partial
        }
      ],
      evidence: [
        %{label: "Suite", path: "test/attractor_ex/conformance/agent_loop_conformance_test.exs"},
        %{
          label: "Command",
          command: "mix test test/attractor_ex/conformance/agent_loop_conformance_test.exs"
        }
      ]
    },
    %{
      id: :unified_llm,
      label: "Unified LLM",
      description: "Provider-agnostic request, JSON, and streaming contracts.",
      scenarios: [
        %{
          id: "generate-object",
          title: "Generates a JSON object through the provider-agnostic client.",
          status: :implemented
        },
        %{
          id: "stream-object",
          title: "Accumulates streaming output into a normalized JSON object.",
          status: :implemented
        }
      ],
      evidence: [
        %{label: "Suite", path: "test/attractor_ex/conformance/unified_llm_conformance_test.exs"},
        %{
          label: "Command",
          command: "mix test test/attractor_ex/conformance/unified_llm_conformance_test.exs"
        }
      ]
    }
  ]

  @gap_ledger [
    %{
      id: "CONF-STATE-001",
      area: "State",
      status: "partial",
      summary:
        "The file-backed HTTP manager now proves restart persistence, but the repo still lacks a wider cold-boot durability benchmark across process boundaries.",
      evidence_path: "test/attractor_ex/conformance/state_conformance_test.exs",
      roadmap_path: "docs/plan/02-runtime-foundation.md"
    },
    %{
      id: "CONF-TRANSPORT-001",
      area: "Transport",
      status: "partial",
      summary:
        "The public HTTP suite covers create/status/questions/answers, but SSE replay remains covered by focused transport tests rather than this benchmark-grade harness.",
      evidence_path: "test/attractor_ex/http_test.exs",
      roadmap_path: "docs/plan/03-operator-surface-and-debugger.md"
    },
    %{
      id: "CONF-AGENT-001",
      area: "Agent loop",
      status: "partial",
      summary:
        "The benchmark suite proves the default provider preset and event surface, but deeper multi-provider subagent matrices still live in focused session tests.",
      evidence_path: "test/attractor_ex/agent/session_test.exs",
      roadmap_path: "docs/plan/06-unified-llm-and-agent-platform.md"
    },
    %{
      id: "CONF-LLM-001",
      area: "Unified LLM",
      status: "partial",
      summary:
        "The scoreboard proves provider-agnostic JSON and stream normalization, while provider-native parity gaps remain tracked in the unified LLM compliance matrix.",
      evidence_path: "test/attractor_ex/conformance/unified_llm_conformance_test.exs",
      roadmap_path: "docs/plan/06-unified-llm-and-agent-platform.md"
    }
  ]

  @verification_commands [
    "mix test test/attractor_ex/conformance",
    "mix test test/attractor_ex/http_test.exs",
    "mix test test/attractor_ex/agent/session_test.exs",
    "mix test test/attractor_ex/llm_client_test.exs"
  ]

  def summary do
    suites = Enum.map(@suites, &decorate_suite/1)

    %{
      title: "Conformance and proof",
      score: score(),
      total_scenarios: Enum.reduce(suites, 0, &(&1.scenario_count + &2)),
      implemented_scenarios: Enum.reduce(suites, 0, &(&1.implemented_count + &2)),
      suites: suites,
      gap_ledger: @gap_ledger,
      verification_commands: @verification_commands
    }
  end

  def score do
    @suite_scores
    |> Map.values()
    |> Enum.sum()
    |> Kernel./(map_size(@suite_scores))
    |> Float.round(2)
  end

  defp decorate_suite(suite) do
    implemented_count =
      Enum.count(suite.scenarios, fn scenario -> scenario.status == :implemented end)

    partial_count =
      Enum.count(suite.scenarios, fn scenario -> scenario.status == :partial end)

    suite
    |> Map.put(:score, Map.fetch!(@suite_scores, suite.id))
    |> Map.put(:scenario_count, length(suite.scenarios))
    |> Map.put(:implemented_count, implemented_count)
    |> Map.put(:partial_count, partial_count)
    |> Map.put(:status, suite_status(implemented_count, partial_count))
  end

  defp suite_status(implemented_count, 0) when implemented_count > 0, do: "Implemented"
  defp suite_status(_implemented_count, partial_count) when partial_count > 0, do: "Partial"
  defp suite_status(_implemented_count, _partial_count), do: "Planned"
end
