defmodule AttractorExTest.AgentAdapter do
  @moduledoc false

  alias AttractorEx.Agent.ToolCall
  alias AttractorEx.LLM.{Response, Usage}

  def complete(request) do
    scenario = get_in(request.provider_options, ["scenario"]) || "no_tools"
    messages = request.messages || []
    do_complete(scenario, messages, request)
  end

  defp do_complete("no_tools", _messages, _request), do: response("done")

  defp do_complete("single_tool", messages, _request) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "echo", arguments: %{"text" => "hello"}}])
    end
  end

  defp do_complete("single_tool_string_keys", messages, _request) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%{"id" => "call-1", "name" => "echo", "arguments" => %{"text" => "hello"}}])
    end
  end

  defp do_complete("single_tool_atom_keys", messages, _request) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%{id: "call-1", name: "echo", arguments: %{"text" => "hello"}}])
    end
  end

  defp do_complete("single_tool_json_args", messages, _request) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "echo", arguments: "{\"text\":\"hello\"}"}])
    end
  end

  defp do_complete("single_tool_invalid_json_args", messages, _request) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "echo", arguments: "{bad json"}])
    end
  end

  defp do_complete("single_shell_tool", messages, _request) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [%ToolCall{id: "call-1", name: "shell_command", arguments: %{}}])
    end
  end

  defp do_complete("single_shell_tool_with_timeout_arg", messages, _request) do
    if has_tool_message?(messages) do
      response("tool-complete")
    else
      response("", [
        %ToolCall{id: "call-1", name: "shell_command", arguments: %{"timeout_ms" => 300}}
      ])
    end
  end

  defp do_complete("unknown_tool", messages, _request) do
    if has_tool_message?(messages) do
      response("recovered-after-unknown")
    else
      response("", [%ToolCall{id: "call-1", name: "does_not_exist", arguments: %{}}])
    end
  end

  defp do_complete("looping_tool", _messages, _request) do
    response("", [%ToolCall{id: "loop-1", name: "echo", arguments: %{"text" => "repeat"}}])
  end

  defp do_complete("parallel_tools", messages, _request) do
    if has_tool_message?(messages) do
      response("parallel-done")
    else
      response("", [
        %ToolCall{id: "p1", name: "slow", arguments: %{"text" => "a"}},
        %ToolCall{id: "p2", name: "slow", arguments: %{"text" => "b"}}
      ])
    end
  end

  defp do_complete("batched_repeated_calls_once", messages, _request) do
    if has_tool_message?(messages) do
      response("batched-done")
    else
      response("", [
        %ToolCall{id: "b1", name: "echo", arguments: %{"text" => "x"}},
        %ToolCall{id: "b2", name: "echo", arguments: %{"text" => "x"}},
        %ToolCall{id: "b3", name: "echo", arguments: %{"text" => "x"}}
      ])
    end
  end

  defp do_complete("followup_echo", messages, _request) do
    response("ack:" <> last_user_text(messages))
  end

  defp do_complete("echo_reasoning_effort", _messages, request) do
    response("effort:" <> to_string(request.reasoning_effort || "nil"))
  end

  defp do_complete("invalid_tool_calls_shape", _messages, _request) do
    response("shape-done", %{})
  end

  defp do_complete("malformed_tool_call_list", _messages, _request) do
    response("shape-done", [%{}])
  end

  defp do_complete(_scenario, _messages, _request), do: response("done")

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
