defmodule AttractorEx.Agent.ExecutionEnvironment do
  @moduledoc """
  Minimal execution-environment behaviour for agent sessions.
  """

  @callback working_directory(term()) :: String.t()
  @callback platform(term()) :: String.t()
end
