defmodule AttractorEx.Handlers.StackManagerLoop do
  @moduledoc false

  alias AttractorEx.Outcome

  def execute(node, context, graph, _stage_dir, opts) do
    child_dotfile = graph.attrs["stack.child_dotfile"]
    child_workdir = graph.attrs["stack.child_workdir"] || File.cwd!()
    poll_interval = parse_duration_ms(node.attrs["manager.poll_interval"] || "45s")
    max_cycles = parse_int(node.attrs["manager.max_cycles"], 1000)
    stop_condition = node.attrs["manager.stop_condition"] || ""
    actions = parse_actions(node.attrs["manager.actions"] || "observe,wait")

    if truthy?(node.attrs["stack.child_autostart"] || "true") do
      starter = Keyword.get(opts, :manager_start_child, fn _child_dotfile -> :ok end)
      _ = invoke_child_starter(starter, child_dotfile, child_workdir)
    end

    observe = Keyword.get(opts, :manager_observe, fn ctx -> ctx end)
    steer = Keyword.get(opts, :manager_steer, fn ctx, _node -> ctx end)
    stop_eval = Keyword.get(opts, :manager_stop_eval, fn _expr, _ctx -> false end)

    run_loop(
      1,
      max_cycles,
      context,
      actions,
      observe,
      steer,
      stop_eval,
      stop_condition,
      poll_interval
    )
  end

  defp run_loop(
         cycle,
         max_cycles,
         _context,
         _actions,
         _observe,
         _steer,
         _stop_eval,
         _stop_condition,
         _poll_interval
       )
       when cycle > max_cycles do
    Outcome.fail("Max cycles exceeded")
  end

  defp run_loop(
         cycle,
         max_cycles,
         context,
         actions,
         observe,
         steer,
         stop_eval,
         stop_condition,
         poll_interval
       ) do
    next_context =
      context
      |> maybe_observe(actions, observe)
      |> maybe_steer(actions, steer)

    child_status =
      get_in(next_context, ["context.stack.child.status"]) ||
        get_in(next_context, ["context.stack.child", "status"]) || ""

    child_outcome =
      get_in(next_context, ["context.stack.child.outcome"]) ||
        get_in(next_context, ["context.stack.child", "outcome"]) || ""

    cond do
      child_status == "completed" and child_outcome == "success" ->
        Outcome.success(%{}, "Child completed")

      child_status == "failed" ->
        Outcome.fail("Child failed")

      stop_condition != "" and stop_eval.(stop_condition, next_context) ->
        Outcome.success(%{}, "Stop condition satisfied")

      true ->
        if Enum.member?(actions, "wait") and poll_interval > 0 do
          Process.sleep(poll_interval)
        end

        run_loop(
          cycle + 1,
          max_cycles,
          next_context,
          actions,
          observe,
          steer,
          stop_eval,
          stop_condition,
          poll_interval
        )
    end
  end

  defp maybe_observe(context, actions, observe) do
    if Enum.member?(actions, "observe"), do: observe.(context), else: context
  end

  defp maybe_steer(context, actions, steer) do
    if Enum.member?(actions, "steer"), do: steer.(context, %{}), else: context
  end

  defp parse_actions(value) do
    value
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp parse_duration_ms(value) when is_integer(value), do: value

  defp parse_duration_ms(value) when is_binary(value) do
    case Regex.run(~r/^(-?\d+)(ms|s|m|h|d)$/, String.trim(value), capture: :all_but_first) do
      [amount, "ms"] -> String.to_integer(amount)
      [amount, "s"] -> String.to_integer(amount) * 1_000
      [amount, "m"] -> String.to_integer(amount) * 60_000
      [amount, "h"] -> String.to_integer(amount) * 3_600_000
      [amount, "d"] -> String.to_integer(amount) * 86_400_000
      _ -> 45_000
    end
  end

  defp parse_duration_ms(_), do: 45_000

  defp truthy?(value) when is_boolean(value), do: value

  defp truthy?(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["true", "1", "yes"]
  end

  defp truthy?(_), do: false

  defp invoke_child_starter(starter, child_dotfile, child_workdir) when is_function(starter, 2),
    do: starter.(child_dotfile, child_workdir)

  defp invoke_child_starter(starter, child_dotfile, _child_workdir) when is_function(starter, 1),
    do: starter.(child_dotfile)
end
