defmodule AttractorExTest.AgentAdapter do
  @moduledoc false

  alias AttractorEx.Agent.ToolCall
  alias AttractorEx.LLM.{Response, Usage}

  def complete(request) do
    scenario = get_in(request.provider_options, ["scenario"]) || "no_tools"
    messages = request.messages || []
    do_complete(scenario, messages)
  end

  defp do_complete("no_tools", _messages), do: response("done")

  defp do_complete("single_tool", messages) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "echo", arguments: %{"text" => "hello"}}])
    end
  end

  defp do_complete("single_tool_string_keys", messages) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%{"id" => "call-1", "name" => "echo", "arguments" => %{"text" => "hello"}}])
    end
  end

  defp do_complete("single_tool_atom_keys", messages) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%{id: "call-1", name: "echo", arguments: %{"text" => "hello"}}])
    end
  end

  defp do_complete("single_tool_json_args", messages) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "echo", arguments: "{\"text\":\"hello\"}"}])
    end
  end

  defp do_complete("single_tool_invalid_json_args", messages) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "echo", arguments: "{bad json"}])
    end
  end

  defp do_complete("single_shell_tool", messages) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "shell_command", arguments: %{}}])
    end
  end

  defp do_complete("unknown_tool", messages) do
    if has_tool_message?(messages) do
      response("recovered-after-unknown")
    else
      response("", [%ToolCall{id: "call-1", name: "does_not_exist", arguments: %{}}])
    end
  end

  defp do_complete("looping_tool", _messages) do
    response("", [%ToolCall{id: "loop-1", name: "echo", arguments: %{"text" => "repeat"}}])
  end

  defp do_complete("parallel_tools", messages) do
    if has_tool_message?(messages) do
      response("parallel-done")
    else
      response("", [
        %ToolCall{id: "p1", name: "slow", arguments: %{"text" => "a"}},
        %ToolCall{id: "p2", name: "slow", arguments: %{"text" => "b"}}
      ])
    end
  end

  defp do_complete("followup_echo", messages) do
    response("ack:" <> last_user_text(messages))
  end

  defp do_complete("invalid_tool_calls_shape", _messages) do
    response("shape-done", %{})
  end

  defp do_complete(_scenario, _messages), do: response("done")

  defp has_tool_message?(messages) do
    Enum.any?(messages, fn msg -> msg.role == :tool end)
  end

  defp last_user_text(messages) do
    messages
    |> Enum.filter(fn msg -> msg.role == :user end)
    |> List.last()
    |> case do
      nil -> ""
      msg -> msg.content || ""
    end
  end

  defp response(text, tool_calls \\ []) do
    %Response{text: text, tool_calls: tool_calls, usage: %Usage{}, finish_reason: "stop"}
  end
end
