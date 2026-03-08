defmodule AttractorEx.Agent.LocalExecutionEnvironment do
  @moduledoc """
  Local filesystem-backed execution environment for agent sessions.

  It exposes a working directory and a simple platform identifier derived from the host
  operating system.
  """

  @behaviour AttractorEx.Agent.ExecutionEnvironment

  defstruct working_dir: nil

  @type t :: %__MODULE__{working_dir: String.t() | nil}

  @spec new(keyword()) :: t()
  @doc "Builds a local execution environment."
  def new(opts \\ []) do
    %__MODULE__{working_dir: Keyword.get(opts, :working_dir)}
  end

  @impl true
  def working_directory(%__MODULE__{working_dir: nil}) do
    File.cwd!()
  end

  def working_directory(%__MODULE__{working_dir: path}) do
    path
  end

  @impl true
  def platform(_env) do
    os = :os.type()
    "#{elem(os, 0)}-#{elem(os, 1)}"
  end
end
