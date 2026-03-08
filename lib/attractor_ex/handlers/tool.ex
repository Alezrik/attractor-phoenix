defmodule AttractorEx.Handlers.Tool do
  @moduledoc """
  Handler for shell-command tool nodes.

  The handler runs the configured command on the local host, captures stdout and stderr,
  and optionally executes pre- and post-hook commands declared at graph level.
  """

  alias AttractorEx.Outcome

  @doc "Executes a tool node and returns the command output in context updates."
  def execute(node, _context, graph, stage_dir, _opts) do
    command = node.attrs["tool_command"] || node.attrs["command"] || ""
    graph_attrs = Map.get(graph, :attrs) || Map.get(graph, "attrs") || %{}

    if String.trim(command) == "" do
      Outcome.fail("No tool_command specified")
    else
      pre_hook =
        run_hook(
          Map.get(graph_attrs, "tool_hooks.pre"),
          stage_dir,
          "tool_hook_pre.log",
          node,
          command
        )

      result = do_execute(command, node.id)

      post_hook =
        run_hook(
          Map.get(graph_attrs, "tool_hooks.post"),
          stage_dir,
          "tool_hook_post.log",
          node,
          command,
          result
        )

      result
      |> maybe_append_hook_note(pre_hook, "pre")
      |> maybe_append_hook_note(post_hook, "post")
    end
  end

  defp do_execute(command, node_id) do
    {shell, args} =
      case :os.type() do
        {:win32, _} -> {"cmd", ["/c", command]}
        _ -> {"sh", ["-lc", command]}
      end

    try do
      {output, code} = System.cmd(shell, args, stderr_to_stdout: true)

      if code == 0 do
        Outcome.success(
          %{"tool.output" => output, "tools" => %{node_id => output}},
          "Tool completed: #{command}"
        )
      else
        Outcome.fail("Tool command failed (#{code}): #{output}")
      end
    rescue
      error -> Outcome.fail("Tool execution failed: #{Exception.message(error)}")
    end
  end

  defp run_hook(hook, stage_dir, filename, node, command, result \\ nil)

  defp run_hook(nil, _stage_dir, _filename, _node, _command, _result), do: :ok
  defp run_hook("", _stage_dir, _filename, _node, _command, _result), do: :ok

  defp run_hook(hook, stage_dir, filename, node, command, result) do
    {shell, args} =
      case :os.type() do
        {:win32, _} -> {"cmd", ["/c", hook]}
        _ -> {"sh", ["-lc", hook]}
      end

    env =
      [
        {"ATTRACTOR_TOOL_NODE_ID", node.id},
        {"ATTRACTOR_TOOL_COMMAND", command},
        {"ATTRACTOR_TOOL_STATUS", tool_status(result)},
        {"ATTRACTOR_TOOL_ERROR", tool_error(result)}
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {output, code} = System.cmd(shell, args, stderr_to_stdout: true, env: env)

    if output != "" do
      _ = File.write(Path.join(stage_dir, filename), output)
    end

    if code == 0, do: :ok, else: {:error, "hook failed (#{code})"}
  rescue
    error ->
      _ = File.write(Path.join(stage_dir, filename), Exception.message(error))
      {:error, "hook exception: #{Exception.message(error)}"}
  end

  defp maybe_append_hook_note(%Outcome{} = outcome, :ok, _phase), do: outcome

  defp maybe_append_hook_note(%Outcome{} = outcome, {:error, reason}, phase) do
    %{outcome | notes: join_notes(outcome.notes, "#{phase} hook #{reason}")}
  end

  defp tool_status(nil), do: nil
  defp tool_status(%Outcome{status: status}), do: Atom.to_string(status)

  defp tool_error(nil), do: nil
  defp tool_error(%Outcome{failure_reason: reason}), do: reason

  defp join_notes(nil, note), do: note
  defp join_notes("", note), do: note
  defp join_notes(existing, note), do: existing <> "; " <> note
end
