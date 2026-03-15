defmodule AttractorPhoenix.LLMAdapters.OpenAICliTest do
  use ExUnit.Case, async: false

  alias AttractorEx.LLM.{Message, Request}
  alias AttractorPhoenix.LLMAdapters.OpenAICli
  alias AttractorPhoenix.LLMSetup

  setup do
    previous_runner = Application.get_env(:attractor_phoenix, :openai_cli_runner)

    LLMSetup.reset()

    {:ok, _settings} =
      LLMSetup.save_api_keys(%{
        "openai_mode" => "cli",
        "openai_cli_command" => ~s(codex exec --full-auto "{prompt}" --model {model})
      })

    on_exit(fn ->
      restore_env(:attractor_phoenix, :openai_cli_runner, previous_runner)
      LLMSetup.reset()
    end)

    :ok
  end

  test "runs codex cli with prompt and model substitution" do
    parent = self()

    Application.put_env(:attractor_phoenix, :openai_cli_runner, fn command, args, _opts ->
      send(parent, {:cli_invocation, command, args})

      {"digraph generated_pipeline { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
       0}
    end)

    request = %Request{
      model: "codex-5.3",
      messages: [
        %Message{role: :system, content: "System guidance"},
        %Message{role: :user, content: "Build a tiny flow"}
      ]
    }

    assert %AttractorEx.LLM.Response{text: text} = OpenAICli.complete(request)
    assert text =~ "digraph generated_pipeline"

    if match?({:win32, _}, :os.type()) do
      assert_receive {:cli_invocation, command, args}

      assert Path.basename(String.downcase(command)) in [
               "powershell.exe",
               "powershell",
               "pwsh.exe",
               "pwsh"
             ]

      file_index = Enum.find_index(args, &(&1 == "-File"))
      assert is_integer(file_index)

      script = Enum.at(args, file_index + 1)
      exec_args = Enum.drop(args, file_index + 2)
      assert ["exec", "--full-auto", prompt, "--model", "codex-5.3"] = exec_args

      assert String.ends_with?(String.downcase(script), "codex.ps1")
      assert prompt =~ "System guidance"
      assert prompt =~ "Build a tiny flow"
    else
      assert_receive {:cli_invocation, "codex",
                      ["exec", "--full-auto", prompt, "--model", "codex-5.3"]}

      assert prompt =~ "System guidance"
      assert prompt =~ "Build a tiny flow"
    end
  end

  test "returns helpful error when cli exits non-zero" do
    Application.put_env(:attractor_phoenix, :openai_cli_runner, fn _command, _args, _opts ->
      {"quota problem", 1}
    end)

    request = %Request{model: "codex-5.3", messages: [%Message{role: :user, content: "hi"}]}

    assert {:error, message} = OpenAICli.complete(request)
    assert message =~ "exited with code 1"
  end

  test "uses cmd /c for windows cmd shims" do
    if match?({:win32, _}, :os.type()) do
      parent = self()

      Application.put_env(:attractor_phoenix, :openai_cli_runner, fn command, args, _opts ->
        send(parent, {:cli_invocation, command, args})
        {"ok", 0}
      end)

      {:ok, _settings} =
        LLMSetup.save_api_keys(%{
          "openai_mode" => "cli",
          "openai_cli_command" =>
            ~s(C:/Users/ex_ra/AppData/Roaming/npm/codex.cmd exec --full-auto "{prompt}")
        })

      request = %Request{model: "codex-5.3", messages: [%Message{role: :user, content: "hi"}]}

      assert %AttractorEx.LLM.Response{text: "ok"} = OpenAICli.complete(request)
      assert_receive {:cli_invocation, command, args}

      assert Path.basename(String.downcase(command)) in [
               "powershell.exe",
               "powershell",
               "pwsh.exe",
               "pwsh"
             ]

      file_index = Enum.find_index(args, &(&1 == "-File"))
      assert is_integer(file_index)

      script = Enum.at(args, file_index + 1)
      assert String.ends_with?(String.downcase(script), "codex.ps1")
      assert Enum.drop(args, file_index + 2) == ["exec", "--full-auto", "hi"]
    end
  end

  test "falls back to cmd.exe when a windows batch shim has no powershell companion" do
    if match?({:win32, _}, :os.type()) do
      parent = self()
      unique = System.unique_integer([:positive])
      temp_dir = Path.join(System.tmp_dir!(), "openai-cli-test-#{unique}")
      shim_path = Path.join(temp_dir, "custom.cmd")

      File.mkdir_p!(temp_dir)
      File.write!(shim_path, "@echo off\r\n")

      on_exit(fn -> File.rm_rf(temp_dir) end)

      Application.put_env(:attractor_phoenix, :openai_cli_runner, fn command, args, _opts ->
        send(parent, {:cli_invocation, command, args})
        {"ok", 0}
      end)

      {:ok, _settings} =
        LLMSetup.save_api_keys(%{
          "openai_mode" => "cli",
          "openai_cli_command" => ~s(#{shim_path} exec --full-auto "{prompt}")
        })

      request = %Request{
        model: "codex-5.3",
        messages: [%Message{role: :user, content: "hi there"}]
      }

      assert %AttractorEx.LLM.Response{text: "ok"} = OpenAICli.complete(request)
      assert_receive {:cli_invocation, command, ["/d", "/s", "/c", cmd_line]}
      assert Path.basename(String.downcase(command)) in ["cmd.exe", "cmd"]
      assert cmd_line =~ "custom.cmd"
      assert cmd_line =~ " exec "
      assert cmd_line =~ "--full-auto"
      assert cmd_line =~ "hi there"
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
