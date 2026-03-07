defmodule AttractorEx.Interviewers.Console do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  alias AttractorEx.Interviewers.Payload

  @impl true
  def ask(node, choices, _context, _opts) do
    question = Payload.question(node, choices)

    details =
      [
        prompt_line(node.attrs["prompt"]),
        default_line(node.attrs["human.default_choice"]),
        timeout_line(node.attrs["human.timeout"]),
        input_mode_line(question)
      ]
      |> Enum.reject(&is_nil/1)

    prompt =
      ["Select a choice for human gate `", node.id, "`:"] ++
        Enum.map(details, &["\n", &1]) ++
        Enum.map(choices, fn choice -> "\n- [#{choice.key}] #{choice.label}" end) ++
        ["\n> "]

    case IO.gets(IO.ANSI.format(prompt, true)) do
      value when is_binary(value) ->
        {:ok, value |> Payload.parse_console_input() |> Payload.normalize_single_answer(question)}

      _ ->
        {:timeout}
    end
  end

  @impl true
  def ask_multiple(node, choices, _context, _opts) do
    question = Payload.question(node, choices)

    case IO.gets(IO.ANSI.format(multiple_prompt(node, choices, question), true)) do
      value when is_binary(value) ->
        parsed = parse_multiple_input(value)
        {:ok, Payload.normalize_multiple_answer(parsed, question)}

      _ ->
        {:timeout}
    end
  end

  @impl true
  def inform(node, payload, _context, _opts) do
    _ = IO.puts("Info for `#{node.id}`: #{Payload.message(payload)}")
    :ok
  end

  defp multiple_prompt(node, choices, question) do
    details =
      [
        prompt_line(node.attrs["prompt"]),
        default_line(node.attrs["human.default_choice"]),
        timeout_line(node.attrs["human.timeout"]),
        input_mode_line(question),
        "Enter comma-separated keys or JSON payload."
      ]
      |> Enum.reject(&is_nil/1)

    ["Select one or more choices for human gate `", node.id, "`:"] ++
      Enum.map(details, &["\n", &1]) ++
      Enum.map(choices, fn choice -> "\n- [#{choice.key}] #{choice.label}" end) ++
      ["\n> "]
  end

  defp parse_multiple_input(value) do
    case Payload.parse_console_input(value) do
      parsed when is_binary(parsed) ->
        parsed
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      parsed ->
        parsed
    end
  end

  defp prompt_line(value) when is_binary(value) and value != "", do: "Prompt: #{value}"
  defp prompt_line(_value), do: nil

  defp default_line(value) when is_binary(value) and value != "", do: "Default: #{value}"
  defp default_line(_value), do: nil

  defp timeout_line(value) when is_binary(value) and value != "", do: "Timeout: #{value}"
  defp timeout_line(value) when is_integer(value) and value > 0, do: "Timeout: #{value}"
  defp timeout_line(_value), do: nil

  defp input_mode_line(question) do
    case get_in(question, [:metadata, "input_mode"]) do
      value when is_binary(value) and value != "" -> "Input: #{value}"
      _ -> nil
    end
  end
end
