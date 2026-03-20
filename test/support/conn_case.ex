defmodule AttractorPhoenixWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AttractorPhoenixWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias AttractorEx.HTTP.Manager

  using do
    quote do
      # The default endpoint for testing
      @endpoint AttractorPhoenixWeb.Endpoint

      use AttractorPhoenixWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import AttractorPhoenixWeb.ConnCase
    end
  end

  setup _tags do
    reset_http_runtime!()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defp reset_http_runtime! do
    attractor_http_opts = Application.fetch_env!(:attractor_phoenix, :attractor_http)
    manager = Keyword.fetch!(attractor_http_opts, :manager)

    case Process.whereis(manager) do
      nil -> {:error, :manager_not_running}
      _pid -> :ok = Manager.reset(manager)
    end
  end
end
