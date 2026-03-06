defmodule AttractorEx.Handlers.Tool do
  @moduledoc false

  alias AttractorEx.Outcome

  def execute(node, _context, _graph, _stage_dir, _opts) do
    command = node.attrs["tool_command"] || node.attrs["command"] || ""

    if String.trim(command) == "" do
      Outcome.fail("No tool_command specified")
    else
      do_execute(command, node.id)
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
end
