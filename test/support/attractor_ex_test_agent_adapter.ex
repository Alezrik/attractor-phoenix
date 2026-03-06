defmodule AttractorExTest.AgentAdapter do
  @moduledoc false

  alias AttractorEx.Agent.ToolCall
  alias AttractorEx.LLM.{Response, Usage}

  def complete(request) do
    scenario = get_in(request.provider_options, ["scenario"]) || "no_tools"
    messages = request.messages || []

    case scenario do
      "no_tools" ->
        response("done")

      "single_tool" ->
        if has_tool_message?(messages) do
          response("tool-complete")
        else
          response("", [%ToolCall{id: "call-1", name: "echo", arguments: %{"text" => "hello"}}])
        end

      "single_shell_tool" ->
        if has_tool_message?(messages) do
          response("tool-complete")
        else
          response("", [%ToolCall{id: "call-1", name: "shell_command", arguments: %{}}])
        end

      "unknown_tool" ->
        if has_tool_message?(messages) do
          response("recovered-after-unknown")
        else
          response("", [%ToolCall{id: "call-1", name: "does_not_exist", arguments: %{}}])
        end

      "looping_tool" ->
        response("", [%ToolCall{id: "loop-1", name: "echo", arguments: %{"text" => "repeat"}}])

      "parallel_tools" ->
        if has_tool_message?(messages) do
          response("parallel-done")
        else
          response("", [
            %ToolCall{id: "p1", name: "slow", arguments: %{"text" => "a"}},
            %ToolCall{id: "p2", name: "slow", arguments: %{"text" => "b"}}
          ])
        end

      "followup_echo" ->
        response("ack:" <> last_user_text(messages))

      _ ->
        response("done")
    end
  end

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
