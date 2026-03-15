defmodule AttractorPhoenix.DotGeneratorTest do
  use ExUnit.Case, async: false

  alias AttractorPhoenix.{DotGenerator, LLMSetup}

  setup do
    previous_llm = Application.get_env(:attractor_phoenix, :attractor_ex_llm)
    previous_fetcher = Application.get_env(:attractor_phoenix, :llm_model_fetcher)
    previous_adapters = Application.get_env(:attractor_phoenix, :llm_provider_adapters)
    previous_cli_runner = Application.get_env(:attractor_phoenix, :openai_cli_runner)

    Application.put_env(:attractor_phoenix, :attractor_ex_llm,
      providers: %{"openai" => AttractorPhoenixTest.DotGeneratorAdapter},
      default_provider: "openai"
    )

    Application.put_env(:attractor_phoenix, :llm_model_fetcher, fn
      "openai", _api_key ->
        {:ok, [%{id: "gpt-test", provider: "openai", label: "gpt-test", raw: %{}}]}

      _provider, _api_key ->
        {:ok, []}
    end)

    LLMSetup.reset()
    {:ok, _settings} = LLMSetup.save_api_keys(%{"openai" => "test-key"})
    {:ok, _settings} = LLMSetup.refresh_models()
    {:ok, _settings} = LLMSetup.set_default("openai", "gpt-test")

    on_exit(fn ->
      restore_env(:attractor_phoenix, :attractor_ex_llm, previous_llm)
      restore_env(:attractor_phoenix, :llm_model_fetcher, previous_fetcher)
      restore_env(:attractor_phoenix, :llm_provider_adapters, previous_adapters)
      restore_env(:attractor_phoenix, :openai_cli_runner, previous_cli_runner)
      LLMSetup.reset()
    end)

    :ok
  end

  test "generates validated dot from a natural-language prompt" do
    assert {:ok, dot} = DotGenerator.generate("Build a release workflow with planning and exit")
    assert dot =~ "digraph generated_pipeline"
    assert dot =~ ~s(llm_model="gpt-test")
    assert dot =~ "start -> plan"
  end

  test "returns validation errors when generated output is not valid dot" do
    assert {:error, message} = DotGenerator.generate("broken output please")
    assert message =~ "Generated DOT could not be parsed"
  end

  test "extracts dot from wrapped markdown output" do
    assert {:ok, dot} = DotGenerator.generate("wrapped output please")
    assert dot =~ "digraph generated_pipeline"
    assert dot =~ "start -> plan"
  end

  test "extracts dot from noisy output around a valid graph" do
    assert {:ok, dot} = DotGenerator.generate("noisy output please")
    assert dot =~ "digraph generated_pipeline"
    assert dot =~ "start -> plan"
    refute dot =~ "Codex session starting"
    refute dot =~ "Generation complete"
  end

  test "returns an error tuple when the provider crashes" do
    assert {:error, message} = DotGenerator.generate("explode output please")
    assert message =~ "DOT generation crashed"
    assert message =~ "adapter exploded while generating dot"
  end

  test "falls back to setup-backed provider adapters when attr_ex_llm config is empty" do
    Application.delete_env(:attractor_phoenix, :attractor_ex_llm)

    Application.put_env(:attractor_phoenix, :llm_provider_adapters, %{
      "openai" => AttractorPhoenixTest.DotGeneratorAdapter
    })

    assert {:ok, dot} = DotGenerator.generate("Build a release workflow")
    assert dot =~ "digraph generated_pipeline"
  end

  test "uses codex cli when openai setup mode is cli" do
    Application.delete_env(:attractor_phoenix, :attractor_ex_llm)

    Application.put_env(:attractor_phoenix, :openai_cli_runner, fn _command, _args, _opts ->
      {"digraph generated_pipeline {\n  start [shape=Mdiamond]\n  done [shape=Msquare]\n  start -> done\n}",
       0}
    end)

    {:ok, _settings} =
      LLMSetup.save_api_keys(%{
        "openai" => "",
        "openai_mode" => "cli",
        "openai_cli_command" => "codex exec --full-auto {prompt}"
      })

    {:ok, _settings} = LLMSetup.refresh_models()

    assert {:ok, dot} =
             DotGenerator.generate("Build something", provider: "openai", model: "codex-5.3")

    assert dot =~ "digraph generated_pipeline"
  end

  test "returns a helpful error when no discovered default exists" do
    LLMSetup.reset()

    assert {:error, message} = DotGenerator.generate("Build something")
    assert message =~ "No provider/model is configured"
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
