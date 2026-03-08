defmodule AttractorEx.Interviewers.Payload do
  @moduledoc """
  Shared question and answer normalization for interviewer adapters.

  This module keeps console, queue, callback, recording, and HTTP interviewers on the
  same wire format so `wait.human` behavior stays consistent across transports.
  """

  alias AttractorEx.HumanGate

  @doc "Builds the normalized question payload for a human-gate node."
  def question(node, choices, opts \\ []) do
    timeout_ms = timeout_ms(Keyword.get(opts, :timeout, Map.get(node.attrs, "human.timeout")))
    question_type = question_type(node, choices)
    multiple? = multiple_choice?(node)
    required? = required?(node)
    normalized_choices = Enum.map(choices, &normalize_choice/1)
    input_mode = input_mode(node, question_type, normalized_choices)

    %{
      id: node.id,
      text: Map.get(node.attrs, "prompt", "Choose a path"),
      type: question_type,
      options: normalized_choices,
      default: Map.get(node.attrs, "human.default_choice"),
      timeout_seconds: timeout_ms / 1000,
      stage: node.id,
      multiple: multiple?,
      required: required?,
      metadata: %{
        "node_id" => node.id,
        "question_type" => question_type,
        "timeout" => Map.get(node.attrs, "human.timeout"),
        "default_choice" => Map.get(node.attrs, "human.default_choice"),
        "multiple" => multiple?,
        "choice_count" => length(normalized_choices),
        "input_mode" => input_mode,
        "required" => required?
      }
    }
  end

  @doc "Normalizes an answer for single-select questions."
  def normalize_single_answer(answer, question) do
    answer
    |> normalize_answer(question)
    |> unwrap_single()
  end

  @doc "Normalizes an answer for multi-select questions."
  def normalize_multiple_answer(answer, question) do
    answer
    |> normalize_answer(question)
    |> List.wrap()
  end

  @doc "Builds a structured answer payload including matched options."
  def answer_payload(answer, question) do
    normalized =
      if question.multiple do
        normalize_multiple_answer(answer, question)
      else
        normalize_single_answer(answer, question)
      end

    values = List.wrap(normalized)

    %{
      question_id: question.id,
      question_type: question.type,
      multiple: question.multiple,
      required: question.required,
      input_mode: get_in(question, [:metadata, "input_mode"]),
      normalized: normalized,
      values: values,
      matched_options: matched_options(values, question.options)
    }
  end

  @doc "Extracts a displayable message from an interviewer payload."
  def message(payload) when is_map(payload) do
    Map.get(payload, "message", Map.get(payload, :message, inspect(payload)))
  end

  def message(payload), do: to_string(payload)

  @doc "Parses console input, decoding JSON objects and arrays when present."
  def parse_console_input(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      trimmed == "" ->
        ""

      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, decoded} -> decoded
          _ -> trimmed
        end

      true ->
        trimmed
    end
  end

  @doc "Normalizes timeout values such as `30s`, `5m`, or `1d` into milliseconds."
  def timeout_ms(value) when is_integer(value) and value > 0, do: value

  def timeout_ms(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {parsed, ""} when parsed > 0 ->
        parsed * 1000

      _ ->
        case Regex.run(~r/^(\d+)(ms|s|m|h|d)$/, trimmed, capture: :all_but_first) do
          [amount, "ms"] -> String.to_integer(amount)
          [amount, "s"] -> String.to_integer(amount) * 1_000
          [amount, "m"] -> String.to_integer(amount) * 60_000
          [amount, "h"] -> String.to_integer(amount) * 3_600_000
          [amount, "d"] -> String.to_integer(amount) * 86_400_000
          _ -> 60_000
        end
    end
  end

  def timeout_ms(_value), do: 60_000

  @doc "Returns whether a node is configured for multi-select input."
  def multiple_choice?(node), do: truthy?(Map.get(node.attrs, "human.multiple"))

  @doc "Returns whether a human answer is required for the node."
  def required?(node) do
    value = Map.get(node.attrs, "human.required")

    cond do
      is_nil(value) -> true
      truthy?(value) -> true
      falsey?(value) -> false
      true -> true
    end
  end

  @doc "Infers the interviewer question type from node metadata and choice shape."
  def question_type(node, choices) do
    cond do
      multiple_choice?(node) ->
        "MULTIPLE_CHOICE"

      choices == [] ->
        "FREEFORM"

      confirmation_choice?(choices) ->
        "CONFIRMATION"

      yes_no_choices?(choices) ->
        "YES_NO"

      true ->
        "MULTIPLE_CHOICE"
    end
  end

  @doc "Returns the preferred input mode for the normalized question."
  def input_mode(node, question_type, choices) do
    case Map.get(node.attrs, "human.input") do
      value when is_binary(value) ->
        value
        |> String.trim()
        |> String.downcase()
        |> case do
          "" -> default_input_mode(question_type, choices)
          normalized -> normalized
        end

      _ ->
        default_input_mode(question_type, choices)
    end
  end

  @doc "Normalizes a single choice map into the shared interviewer shape."
  def normalize_choice(choice) when is_map(choice) do
    %{
      "key" => Map.get(choice, :key) || Map.get(choice, "key"),
      "label" => Map.get(choice, :label) || Map.get(choice, "label"),
      "to" => Map.get(choice, :to) || Map.get(choice, "to")
    }
  end

  def normalize_choice(choice), do: %{"value" => choice}

  @doc "Normalizes arbitrary answer values into comparable tokens."
  def normalize_token(nil), do: ""
  def normalize_token(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  def normalize_token(value), do: HumanGate.normalize_token(value)

  @doc "Extracts the answer field from common structured answer payload shapes."
  def extract_answer(answer) when is_map(answer) do
    answer["answers"] ||
      answer[:answers] ||
      answer["values"] ||
      answer[:values] ||
      answer["selected"] ||
      answer[:selected] ||
      answer["selection"] ||
      answer[:selection] ||
      answer["answer"] ||
      answer[:answer] ||
      answer["value"] ||
      answer[:value] ||
      answer["key"] ||
      answer[:key] ||
      answer["keys"] ||
      answer[:keys]
  end

  def extract_answer(_answer), do: nil

  defp normalize_answer(answer, %{type: "YES_NO"} = question) when is_map(answer) do
    answer
    |> extract_answer()
    |> normalize_answer(question)
  end

  defp normalize_answer(answer, %{type: "YES_NO"}) when is_binary(answer) do
    case normalize_token(answer) do
      value when value in ["true", "yes", "y", "approve", "approved", "confirm", "confirmed"] ->
        "yes"

      value when value in ["false", "no", "n", "reject", "rejected", "cancel", "cancelled"] ->
        "no"

      _ ->
        String.trim(answer)
    end
  end

  defp normalize_answer(answer, %{type: "YES_NO"}) when is_boolean(answer) do
    if answer, do: "yes", else: "no"
  end

  defp normalize_answer(answer, %{type: "CONFIRMATION"} = question) when is_map(answer) do
    answer
    |> extract_answer()
    |> normalize_answer(question)
  end

  defp normalize_answer(answer, %{type: "CONFIRMATION"}) when is_binary(answer) do
    case normalize_token(answer) do
      value when value in ["true", "yes", "y", "approve", "approved", "confirm", "confirmed"] ->
        "confirm"

      value when value in ["false", "no", "n", "reject", "rejected", "cancel", "cancelled"] ->
        "cancel"

      _ ->
        String.trim(answer)
    end
  end

  defp normalize_answer(answer, %{type: "CONFIRMATION"}) when is_boolean(answer) do
    if answer, do: "confirm", else: "cancel"
  end

  defp normalize_answer(answer, question) when is_map(answer) do
    candidate = extract_answer(answer)

    if is_nil(candidate) do
      answer
    else
      normalize_answer(candidate, question)
    end
  end

  defp normalize_answer(answer, question) when is_list(answer) do
    Enum.map(answer, &normalize_answer(&1, question))
  end

  defp normalize_answer(answer, _question) when is_binary(answer), do: String.trim(answer)
  defp normalize_answer(answer, _question), do: answer

  defp matched_options(values, options) do
    values
    |> Enum.map(&match_option(&1, options))
    |> Enum.reject(&is_nil/1)
  end

  defp match_option(value, options) do
    normalized = normalize_token(value)

    Enum.find(options, fn option ->
      normalize_token(option["key"]) == normalized or
        normalize_token(option["label"]) == normalized or
        normalize_token(option["to"]) == normalized
    end)
  end

  defp unwrap_single([value]), do: value
  defp unwrap_single(value), do: value

  defp confirmation_choice?([_choice]), do: true
  defp confirmation_choice?(_choices), do: false

  defp yes_no_choices?(choices) when length(choices) == 2 do
    normalized =
      choices
      |> Enum.flat_map(fn choice -> [choice[:key], choice[:label], choice[:to]] end)
      |> Enum.map(&normalize_token/1)
      |> Enum.reject(&(&1 == ""))

    Enum.any?(normalized, &(&1 in ["yes", "y", "approve", "approved"])) and
      Enum.any?(normalized, &(&1 in ["no", "n", "reject", "rejected"]))
  end

  defp yes_no_choices?(_choices), do: false

  defp default_input_mode("FREEFORM", _choices), do: "text"
  defp default_input_mode("YES_NO", _choices), do: "boolean"
  defp default_input_mode("CONFIRMATION", _choices), do: "confirmation"
  defp default_input_mode("MULTIPLE_CHOICE", [_]), do: "single_select"
  defp default_input_mode("MULTIPLE_CHOICE", _choices), do: "multi_select"

  defp truthy?(value) when is_boolean(value), do: value
  defp truthy?(value) when is_binary(value), do: normalize_token(value) in ["true", "1", "yes"]
  defp truthy?(_value), do: false

  defp falsey?(value) when is_boolean(value), do: not value
  defp falsey?(value) when is_binary(value), do: normalize_token(value) in ["false", "0", "no"]
  defp falsey?(_value), do: false
end
