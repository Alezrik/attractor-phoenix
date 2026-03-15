defmodule AttractorPhoenix.LLMAdapters.OpenAICli do
  @moduledoc false

  @behaviour AttractorEx.LLM.ProviderAdapter

  alias AttractorEx.LLM.{Message, Request, Response, Usage}
  alias AttractorPhoenix.LLMSetup

  @impl true
  def complete(%Request{} = request) do
    with {:ok, command_template} <- command_template(),
         {:ok, output} <- run_cli(command_template, request) do
      %Response{
        id: "openai_cli",
        text: String.trim(output),
        finish_reason: "stop",
        usage: %Usage{},
        raw: %{"source" => "cli"}
      }
    end
  end

  defp command_template do
    case LLMSetup.provider_cli_command("openai") do
      nil ->
        {:error,
         "OpenAI CLI command is missing. Visit Setup and configure a Codex command template."}

      template ->
        {:ok, template}
    end
  end

  defp run_cli(command_template, %Request{} = request) do
    prompt_text = build_prompt_text(request)
    {command, args} = command_args(command_template, prompt_text, request.model)
    {command, args} = normalize_command(command, args)
    runner = Application.get_env(:attractor_phoenix, :openai_cli_runner, &System.cmd/3)

    try do
      case runner.(command, args, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, output}

        {output, status} ->
          {:error, "Codex CLI exited with code #{status}: #{String.trim(output)}"}
      end
    rescue
      error in [ArgumentError] ->
        {:error, Exception.message(error)}
    catch
      :exit, reason ->
        {:error, "Codex CLI failed to start: #{inspect(reason)}"}
    end
  end

  defp normalize_command(command, args) do
    executable = System.find_executable(command) || command

    cond do
      windows_cmd_shim?(executable) ->
        normalize_windows_cmd_shim(executable, args)

      true ->
        {executable, args}
    end
  end

  defp normalize_windows_cmd_shim(executable, args) do
    case powershell_shim(executable) do
      {:ok, shell, script} ->
        {shell, powershell_args(shell, script, args)}

      :error ->
        {cmd_executable(), ["/d", "/s", "/c", cmd_command_line([executable | args])]}
    end
  end

  defp command_args(template, prompt, model) do
    prompt_token = "__ATTRACTOR_PROMPT__"
    model_token = "__ATTRACTOR_MODEL__"

    split_args =
      template
      |> String.replace("{prompt}", prompt_token)
      |> String.replace("{model}", model_token)
      |> OptionParser.split()

    {args, prompt_inserted?} =
      Enum.map_reduce(split_args, false, fn arg, inserted? ->
        cond do
          arg == prompt_token -> {prompt, true}
          arg == model_token -> {model || "", inserted?}
          true -> {arg, inserted?}
        end
      end)

    args =
      args
      |> Enum.reject(&(&1 == ""))
      |> then(fn parsed -> if prompt_inserted?, do: parsed, else: parsed ++ [prompt] end)

    [command | command_args] = args
    {command, command_args}
  end

  defp build_prompt_text(%Request{} = request) do
    system =
      request.messages
      |> Enum.filter(&(&1.role in [:system, :developer]))
      |> Enum.map_join("\n\n", &Message.content_text(&1.content))

    prompt =
      request.messages
      |> Enum.reject(&(&1.role in [:system, :developer]))
      |> Enum.map_join("\n", &Message.content_text(&1.content))

    [system, prompt]
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp powershell_shim(executable) do
    script = Path.rootname(executable) <> ".ps1"
    shell = System.find_executable("powershell") || System.find_executable("pwsh")

    if is_binary(shell) and File.exists?(script) do
      {:ok, shell, script}
    else
      :error
    end
  end

  defp powershell_args(shell, script, args) do
    base_args =
      if powershell_supports_execution_policy?(shell) do
        ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script]
      else
        ["-NoProfile", "-File", script]
      end

    base_args ++ args
  end

  defp powershell_supports_execution_policy?(shell) do
    shell
    |> Path.basename()
    |> String.downcase()
    |> then(&(&1 in ["powershell", "powershell.exe"]))
  end

  defp cmd_executable do
    System.find_executable("cmd") || "cmd"
  end

  defp cmd_command_line(parts) do
    Enum.map_join(parts, " ", &cmd_quote/1)
  end

  defp cmd_quote(arg) do
    escaped =
      arg
      |> String.replace("%", "%%")
      |> String.replace("\"", "\\\"")

    if escaped == "" or String.match?(escaped, ~r/[\s"&|<>()^]/) do
      ~s("#{escaped}")
    else
      escaped
    end
  end

  defp windows_cmd_shim?(executable) do
    match?({:win32, _}, :os.type()) and
      (String.ends_with?(String.downcase(executable), ".cmd") or
         String.ends_with?(String.downcase(executable), ".bat"))
  end
end
