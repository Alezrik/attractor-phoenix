defmodule AttractorEx.HTTPHelloWorldTest do
  use ExUnit.Case, async: true

  import OpenApiSpex.TestAssertions
  import Plug.Test

  alias AttractorEx.HTTP.Router

  @router_opts Router.init([])

  setup do
    %{spec: AttractorEx.HTTPHelloWorldApiSpec.spec()}
  end

  test "documents the /status missing pipeline_id error contract", %{spec: spec} do
    conn = Router.call(conn(:get, "/status"), @router_opts)

    assert conn.status == 400
    assert ["application/json; charset=utf-8"] = Plug.Conn.get_resp_header(conn, "content-type")

    payload = Jason.decode!(conn.resp_body)

    assert payload == %{"error" => "pipeline_id is required"}
    assert_schema(payload, "StatusErrorResponse", spec)
  end
end
