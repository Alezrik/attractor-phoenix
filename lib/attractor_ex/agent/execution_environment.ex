defmodule AttractorEx.Agent.ExecutionEnvironment do
  @moduledoc false

  @callback working_directory(term()) :: String.t()
  @callback platform(term()) :: String.t()
end
