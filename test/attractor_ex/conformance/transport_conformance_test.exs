defmodule AttractorEx.Conformance.TransportTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AttractorEx.HTTP.Manager
  alias AttractorEx.HTTP.Router
  alias AttractorExTest.ConformanceFixtures

  @router_opts Router.init([])

  setup do
    start_supervised!(
      {Manager,
       name: AttractorEx.HTTP.Manager,
       store_root: ConformanceFixtures.unique_store_root("transport")}
    )

    start_supervised!({Registry, keys: :duplicate, name: AttractorEx.HTTP.Registry})
    :ok
  end

  test "creates a pipeline over HTTP and exposes status plus context" do
    conn =
      conn(:post, "/pipelines", Jason.encode!(%{"dot" => ConformanceFixtures.transport_dot()}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(conn.resp_body)

    ConformanceFixtures.wait_until(fn ->
      match?(
        {:ok, %{status: :success}},
        Manager.get_pipeline(AttractorEx.HTTP.Manager, pipeline_id)
      )
    end)

    status_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}"), @router_opts)
    context_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}/context"), @router_opts)

    assert %{"status" => "success"} = Jason.decode!(status_conn.resp_body)
    assert %{"context" => %{"run_id" => ^pipeline_id}} = Jason.decode!(context_conn.resp_body)
  end

  test "accepts wait.human answers over the HTTP answer surface" do
    conn =
      conn(:post, "/pipelines", Jason.encode!(%{"dot" => ConformanceFixtures.human_gate_dot()}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(conn.resp_body)

    ConformanceFixtures.wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(AttractorEx.HTTP.Manager, pipeline_id))
    end)

    answer_conn =
      conn(
        :post,
        "/pipelines/#{pipeline_id}/questions/gate/answer",
        Jason.encode!(%{"answer" => "A"})
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert answer_conn.status == 202

    ConformanceFixtures.wait_until(fn ->
      match?(
        {:ok, %{status: :success}},
        Manager.get_pipeline(AttractorEx.HTTP.Manager, pipeline_id)
      )
    end)
  end
end
