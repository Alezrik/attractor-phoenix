defmodule AttractorEx.PhoenixHTTPIntegrationTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AttractorEx.HTTP.Manager
  alias AttractorEx.HTTP.Phoenix, as: HTTPPhoenix
  alias AttractorEx.HTTP.Router

  test "phoenix helper starts manager and registry children and exposes router opts" do
    root_name = Module.concat(__MODULE__, Runtime)
    _supervisor = start_supervised!(HTTPPhoenix.child_spec(name: root_name))

    manager = Module.concat(root_name, Manager)
    registry = Module.concat(manager, Registry)

    assert is_pid(Process.whereis(manager))
    assert is_pid(Process.whereis(registry))
    assert HTTPPhoenix.router_opts(name: root_name) == [manager: manager, registry: registry]
  end

  test "phoenix router opts work with the existing plug router" do
    root_name = Module.concat(__MODULE__, RouterRuntime)
    _supervisor = start_supervised!(HTTPPhoenix.child_spec(name: root_name))

    manager = Module.concat(root_name, Manager)
    opts = HTTPPhoenix.router_opts(name: root_name)

    create_conn =
      conn(
        :post,
        "/pipelines",
        Jason.encode!(%{
          "dot" => """
          digraph {
            start [shape=Mdiamond]
            done [shape=Msquare]
            start -> done
          }
          """
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)

    assert create_conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(create_conn.resp_body)

    wait_until(fn ->
      case Manager.get_pipeline(manager, pipeline_id) do
        {:ok, %{status: status}} -> status in [:success, :fail]
        _ -> false
      end
    end)

    status_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}"), opts)
    assert status_conn.status == 200
    assert %{"status" => "success"} = Jason.decode!(status_conn.resp_body)
  end

  defp wait_until(fun, attempts \\ 50)

  defp wait_until(_fun, 0), do: flunk("condition was not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      receive do
      after
        10 -> wait_until(fun, attempts - 1)
      end
    end
  end
end
