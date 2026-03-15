defmodule AttractorPhoenix.DotGenerator do
  @moduledoc """
  Generates AttractorEx DOT graphs from natural-language prompts using the unified LLM client.
  """

  alias AttractorEx.LLM.{Client, Message, Request}
  alias AttractorEx.{Parser, Validator}
  alias AttractorPhoenix.LLMAdapters
  alias AttractorPhoenix.LLMSetup

  @default_max_tokens 8_192
  @default_temperature 0.2

  @example_simple """
  digraph WriteTests {
      graph [goal="Write and run unit tests for the codebase", label="Test Writer"]
      start   [shape=Mdiamond, label="Start"]
      analyze [label="Analyze Code", prompt="Analyze the codebase structure and identify testable units for: $goal"]
      write   [label="Write Tests", prompt="Write comprehensive unit tests based on the analysis. Goal: $goal"]
      run     [label="Run Tests", prompt="Execute the tests and report results, coverage, and any failures"]
      exit    [shape=Msquare, label="Done"]
      start -> analyze -> write -> run -> exit
  }
  """

  @example_branch """
  digraph ValidateFeature {
      graph [goal="Implement and validate a new feature", label="Feature Validation"]
      start     [shape=Mdiamond, label="Start"]
      implement [label="Implement", prompt="Implement: $goal"]
      validate  [label="Validate", prompt="Run tests and validate the implementation thoroughly"]
      check     [shape=diamond, label="Tests pass?"]
      exit      [shape=Msquare, label="Done"]
      start -> implement -> validate -> check
      check -> exit      [label="yes", condition="outcome=success"]
      check -> implement [label="no", condition="outcome!=success"]
  }
  """

  @example_human_review """
  digraph ContentReview {
      graph [goal="Draft and publish reviewed content", label="Content Review"]
      start  [shape=Mdiamond, label="Start"]
      draft  [label="Draft Content", prompt="Write a draft for: $goal"]
      review [shape=hexagon, label="Human Review", prompt="Please review the draft and approve or request changes"]
      polish [label="Polish", prompt="Apply reviewer feedback and finalize the content"]
      exit   [shape=Msquare, label="Published"]
      start -> draft -> review -> polish -> exit
  }
  """

  @system_prompt """
  You are an expert at writing AttractorEx pipeline files in Graphviz DOT format.
  AttractorEx is a DOT-based runner for multi-stage workflows.

  ## Project Structure

  Every pipeline must be a single `digraph` with graph metadata:

    digraph PipelineName {
      graph [goal="High-level goal description", label="Human-readable name"]
      ...
    }

  ## Node Types (by shape attribute)

  - `Mdiamond` -> Start node. Exactly one required.
  - `Msquare` -> Exit node. At least one required.
  - `box` -> LLM codergen stage.
  - `hexagon` -> Wait for human approval or input.
  - `diamond` -> Conditional branch node.
  - `component` -> Parallel fan-out.
  - `tripleoctagon` -> Parallel fan-in.
  - `parallelogram` -> Tool or shell command stage.
  - `house` -> Stack manager loop.

  ## Key Node Attributes

  - `label` -> display name.
  - `prompt` -> instruction for `box` or `hexagon` nodes.
  - `tool_command` -> shell command for `parallelogram` nodes.
  - `condition` -> routing condition on edges such as `outcome=success` or `outcome!=success`.
  - `timeout` -> duration string like `"30s"` or `"5m"`.
  - `goal_gate` -> optional exit-node condition.

  ## Rules

  1. Generate exactly one valid `digraph`.
  2. Include a `graph [goal=..., label=...]` block.
  3. Use exactly one `Mdiamond` start node.
  4. Use at least one `Msquare` exit node.
  5. All nodes must be reachable from the start node.
  6. Keep node IDs short and readable, like `plan`, `review`, `deploy`, or `done`.
  7. For straightforward requests, prefer a small linear graph.
  8. For retry workflows, use a `diamond` node with conditional edges.
  9. For human approval workflows, use a `hexagon` node with a review prompt.
  10. Output ONLY the raw DOT source for one graph.
  11. Do NOT include markdown fences.
  12. Do NOT explain the graph.
  13. Do NOT include any text before or after the `digraph`.

  ## Examples

  Example 1:
  #{@example_simple}

  Example 2:
  #{@example_branch}

  Example 3:
  #{@example_human_review}
  """

  @spec generate(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def generate(prompt, opts \\ []) when is_binary(prompt) do
    do_generate(prompt, opts)
  rescue
    error ->
      {:error, format_generation_exception(error)}
  catch
    kind, reason ->
      {:error, "DOT generation crashed (#{kind}): #{format_caught_reason(reason)}"}
  end

  defp do_generate(prompt, opts) do
    with {:ok, trimmed_prompt} <- present_prompt(prompt),
         {:ok, client} <- build_client(opts),
         {:ok, provider, model} <- resolve_provider_model(opts),
         request <- build_request(trimmed_prompt, provider, model, opts),
         {:ok, response, _resolved_request} <- Client.complete_with_request(client, request),
         dot <- extract_dot_source(response.text || ""),
         {:ok, validated_dot} <- validate_generated_dot(dot) do
      {:ok, validated_dot}
    else
      {:error, _message} = error -> error
      other -> {:error, "Unexpected DOT generation result: #{inspect(other)}"}
    end
  end

  defp present_prompt(prompt) do
    trimmed = String.trim(prompt)

    if trimmed == "",
      do: {:error, "Describe the pipeline you want to create."},
      else: {:ok, trimmed}
  end

  defp build_client(opts) do
    client = Keyword.get(opts, :llm_client) || configured_client()

    cond do
      map_size(client.providers) == 0 ->
        {:error,
         "DOT generation LLM is not configured. Save an API key in Setup or configure :attractor_ex_llm providers/default_provider."}

      true ->
        {:ok, client}
    end
  end

  defp configured_client do
    env_client = Client.from_env()

    providers =
      setup_provider_adapters()
      |> Enum.reduce(env_client.providers, fn {provider, adapter}, acc ->
        case LLMSetup.provider_mode(provider) do
          "cli" ->
            Map.put(acc, provider, adapter)

          _ ->
            if Map.has_key?(acc, provider), do: acc, else: Map.put(acc, provider, adapter)
        end
      end)

    Client.new(
      providers: providers,
      default_provider: env_client.default_provider || LLMSetup.default_selection().provider,
      middleware: env_client.middleware,
      streaming_middleware: env_client.streaming_middleware
    )
  end

  defp resolve_provider_model(opts) do
    defaults = LLMSetup.default_selection()

    provider =
      blank_to_nil(Keyword.get(opts, :provider)) ||
        defaults.provider ||
        blank_to_nil(generator_config(:provider))

    model =
      blank_to_nil(Keyword.get(opts, :model)) ||
        defaults.model ||
        blank_to_nil(generator_config(:model)) ||
        blank_to_nil(System.get_env("ATTRACTOR_DOT_GENERATOR_MODEL"))

    cond do
      is_nil(provider) and is_nil(model) ->
        {:error,
         "No provider/model is configured. Visit Setup and fetch models first, then choose a default."}

      is_nil(provider) ->
        {:error, "No provider is configured. Visit Setup and choose a default provider/model."}

      is_nil(model) ->
        {:error, "No model is configured. Visit Setup and choose a default provider/model."}

      not available_pair?(provider, model) ->
        {:error,
         "The selected provider/model is not available. Refresh Setup and choose a discovered model."}

      true ->
        {:ok, provider, model}
    end
  end

  defp build_request(prompt, provider, model, opts) do
    %Request{
      model: model,
      provider: provider,
      messages: [
        %Message{role: :system, content: @system_prompt},
        %Message{role: :user, content: user_prompt(prompt)}
      ],
      max_tokens:
        Keyword.get(opts, :max_tokens, generator_config(:max_tokens) || @default_max_tokens),
      temperature:
        Keyword.get(opts, :temperature, generator_config(:temperature) || @default_temperature),
      reasoning_effort:
        Keyword.get(opts, :reasoning_effort, generator_config(:reasoning_effort) || "medium"),
      metadata: %{"feature" => "dot_generator"}
    }
  end

  defp user_prompt(prompt) do
    """
    Create one AttractorEx workflow in Graphviz DOT format for this request:

    #{prompt}

    Output only the raw DOT source for one graph.
    Do not use markdown fences.
    Do not include explanations or any extra text.
    """
    |> String.trim()
  end

  defp extract_dot_source(text) do
    stripped = strip_code_fences(text)

    case extract_digraph_block(stripped) do
      nil -> String.trim(stripped)
      dot -> String.trim(dot)
    end
  end

  defp strip_code_fences(text) do
    fence_regex = ~r/```(?:dot|DOT|graphviz)?\s*\n?([\s\S]+?)\n?```/

    case Regex.run(fence_regex, String.trim(text), capture: :all_but_first) do
      [dot] -> String.trim(dot)
      _ -> String.trim(text)
    end
  end

  defp extract_digraph_block(text) do
    case :binary.match(text, "digraph") do
      {offset, _length} ->
        text
        |> binary_part(offset, byte_size(text) - offset)
        |> take_graph_body()

      :nomatch ->
        nil
    end
  end

  defp take_graph_body(text) do
    graphemes = String.graphemes(text)

    case Enum.find_index(graphemes, &(&1 == "{")) do
      nil ->
        nil

      open_index ->
        case find_matching_graph_end(graphemes, open_index) do
          nil -> nil
          close_index -> graphemes |> Enum.take(close_index + 1) |> Enum.join()
        end
    end
  end

  defp find_matching_graph_end(graphemes, open_index) do
    graphemes
    |> Enum.with_index()
    |> Enum.drop(open_index)
    |> Enum.reduce_while({0, false, false}, fn {char, index}, state ->
      case next_graph_scan_state(char, index, state) do
        {:halt, close_index} -> {:halt, close_index}
        {:cont, next_state} -> {:cont, next_state}
      end
    end)
    |> case do
      index when is_integer(index) -> index
      _ -> nil
    end
  end

  defp next_graph_scan_state(_char, _index, {depth, true, true}) do
    {:cont, {depth, true, false}}
  end

  defp next_graph_scan_state("\\", _index, {depth, true, false}) do
    {:cont, {depth, true, true}}
  end

  defp next_graph_scan_state("\"", _index, {depth, true, false}) do
    {:cont, {depth, false, false}}
  end

  defp next_graph_scan_state(_char, _index, {depth, true, false}) do
    {:cont, {depth, true, false}}
  end

  defp next_graph_scan_state("\"", _index, {depth, false, false}) do
    {:cont, {depth, true, false}}
  end

  defp next_graph_scan_state("{", _index, {depth, false, false}) do
    {:cont, {depth + 1, false, false}}
  end

  defp next_graph_scan_state("}", index, {1, false, false}) do
    {:halt, index}
  end

  defp next_graph_scan_state("}", _index, {depth, false, false}) when depth > 1 do
    {:cont, {depth - 1, false, false}}
  end

  defp next_graph_scan_state(_char, _index, {depth, false, false}) do
    {:cont, {depth, false, false}}
  end

  defp validate_generated_dot(dot) do
    with {:ok, parsed} <- Parser.parse(dot) do
      diagnostics = Validator.validate(parsed)
      errors = Enum.filter(diagnostics, &(&1.severity == :error))

      if errors == [] do
        {:ok, dot}
      else
        {:error, format_diagnostics(errors)}
      end
    else
      {:error, reason} -> {:error, "Generated DOT could not be parsed: #{reason}"}
    end
  end

  defp format_diagnostics(diagnostics) do
    details =
      diagnostics
      |> Enum.map_join("; ", fn diagnostic ->
        prefix =
          cond do
            is_binary(diagnostic.node_id) ->
              "#{diagnostic.node_id}: "

            is_tuple(diagnostic.edge) ->
              "#{elem(diagnostic.edge, 0)}->#{elem(diagnostic.edge, 1)}: "

            true ->
              ""
          end

        prefix <> diagnostic.message
      end)

    "Generated DOT failed validation: " <> details
  end

  defp format_generation_exception(error) do
    "DOT generation crashed: " <> Exception.message(error)
  end

  defp format_caught_reason(reason) when is_binary(reason), do: reason
  defp format_caught_reason(reason), do: inspect(reason)

  defp generator_config(key) do
    :attractor_phoenix
    |> Application.get_env(:attractor_dot_generator, [])
    |> case do
      config when is_list(config) -> Keyword.get(config, key)
      config when is_map(config) -> Map.get(config, key)
      _ -> nil
    end
  end

  defp setup_provider_adapters do
    provider_adapter_modules()
    |> Enum.reduce(%{}, fn {provider, adapters}, acc ->
      case runtime_adapter_for(provider, adapters) do
        nil ->
          acc

        adapter ->
          Map.put(acc, provider, adapter)
      end
    end)
  end

  defp runtime_adapter_for(provider, %{api: api_adapter, cli: cli_adapter}) do
    case LLMSetup.provider_mode(provider) do
      "cli" ->
        cli_adapter

      _ ->
        if LLMSetup.provider_api_key(provider), do: api_adapter, else: nil
    end
  end

  defp runtime_adapter_for(provider, adapter) do
    if LLMSetup.provider_api_key(provider) do
      adapter
    else
      nil
    end
  end

  defp provider_adapter_modules do
    Application.get_env(
      :attractor_phoenix,
      :llm_provider_adapters,
      %{
        "openai" => %{api: LLMAdapters.OpenAI, cli: LLMAdapters.OpenAICli},
        "anthropic" => %{api: LLMAdapters.Anthropic, cli: nil},
        "gemini" => %{api: LLMAdapters.Gemini, cli: nil}
      }
    )
  end

  defp available_pair?(provider, model) do
    LLMSetup.available_models()
    |> Enum.any?(&(&1.provider == provider and &1.id == model))
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
