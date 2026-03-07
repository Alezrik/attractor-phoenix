defmodule AttractorEx.Interviewers.Console do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(node, choices, _context, _opts) do
    details =
      [
        prompt_line(node.attrs["prompt"]),
        default_line(node.attrs["human.default_choice"]),
        timeout_line(node.attrs["human.timeout"])
      ]
      |> Enum.reject(&is_nil/1)

    prompt =
      ["Select a choice for human gate `", node.id, "`:"] ++
        Enum.map(details, &["\n", &1]) ++
        Enum.map(choices, fn choice -> "\n- [#{choice.key}] #{choice.label}" end) ++
        ["\n> "]

    case IO.gets(IO.ANSI.format(prompt, true)) do
      value when is_binary(value) -> {:ok, String.trim(value)}
      _ -> {:timeout}
    end
  end

  @impl true
  def ask_multiple(node, choices, context, opts) do
    case ask(node, choices, context, opts) do
      {:ok, value} ->
        selections =
          value
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, selections}

      other ->
        other
    end
  end

  @impl true
  def inform(node, payload, _context, _opts) do
    message =
      payload
      |> Map.get("message", Map.get(payload, :message, inspect(payload)))

    _ = IO.puts("Info for `#{node.id}`: #{message}")
    :ok
  end

  defp prompt_line(value) when is_binary(value) and value != "", do: "Prompt: #{value}"
  defp prompt_line(_value), do: nil

  defp default_line(value) when is_binary(value) and value != "", do: "Default: #{value}"
  defp default_line(_value), do: nil

  defp timeout_line(value) when is_binary(value) and value != "", do: "Timeout: #{value}"
  defp timeout_line(value) when is_integer(value) and value > 0, do: "Timeout: #{value}"
  defp timeout_line(_value), do: nil
end
