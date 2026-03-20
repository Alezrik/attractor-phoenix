defmodule AttractorExPhx.ClientTest do
  use ExUnit.Case, async: false

  alias AttractorExPhx.Client

  setup do
    Application.put_env(:attractor_phoenix, :attractor_ex_phx_test_listener, self())

    bandit =
      start_supervised!(
        {Bandit, plug: AttractorExPhxTest.Router, scheme: :http, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    previous_config = Application.get_env(:attractor_phoenix, :attractor_http)

    Application.put_env(:attractor_phoenix, :attractor_http,
      port: port,
      ip: {127, 0, 0, 1},
      base_url: "http://127.0.0.1:#{port}"
    )

    on_exit(fn ->
      Application.put_env(:attractor_phoenix, :attractor_http, previous_config)
      Application.delete_env(:attractor_phoenix, :attractor_ex_phx_test_listener)
    end)

    :ok
  end

  test "sends pipeline creation payloads through the adapter client" do
    assert {:ok, %{"pipeline_id" => "adapter-1"}} =
             Client.create_pipeline("digraph { start -> done }", %{"ticket" => "A-1"},
               pipeline_id: "adapter-1",
               logs_root: "tmp/adapter"
             )

    assert_receive {:adapter_request,
                    {:post, "/pipelines", "",
                     %{
                       "dot" => "digraph { start -> done }",
                       "context" => %{"ticket" => "A-1"},
                       "opts" => %{"pipeline_id" => "adapter-1", "logs_root" => "tmp/adapter"}
                     }}}
  end

  test "supports json and binary graph responses" do
    assert {:ok, %{"graph" => %{"id" => "pipeline-1"}}} =
             Client.get_pipeline_graph_json("pipeline-1")

    assert_receive {:adapter_request, {:get, "/pipelines/pipeline-1/graph", "format=json", %{}}}

    assert {:ok, "<svg>pipeline-1</svg>"} = Client.get_pipeline_graph_svg("pipeline-1")

    assert_receive {:adapter_request, {:get, "/pipelines/pipeline-1/graph", "", %{}}}
  end

  test "supports the explicit checkpoint resume control-plane action" do
    assert {:ok, %{"pipeline_id" => "pipeline-1", "recovery_action" => "checkpoint_resume"}} =
             Client.resume_pipeline("pipeline-1")

    assert_receive {:adapter_request, {:post, "/pipelines/pipeline-1/resume", "", %{}}}
  end

  test "returns formatted http errors from the adapter client" do
    assert {:error, "HTTP 400: boom"} = Client.get_pipeline("error")
  end
end
