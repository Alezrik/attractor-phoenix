defmodule AttractorEx.Agent.ExecutionEnvironment do
  @moduledoc """
  Execution-environment behaviour for coding-agent sessions.

  The contract intentionally mirrors the core local tooling surface exposed by
  the agent loop: filesystem reads and writes, directory listing and globbing,
  text search, shell command execution, and a small amount of host metadata.
  """

  @callback working_directory(term()) :: String.t()
  @callback platform(term()) :: String.t()
  @callback read_file(term(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback write_file(term(), String.t(), String.t()) :: :ok | {:error, term()}
  @callback list_directory(term(), String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback glob(term(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @callback grep(term(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}

  @callback shell_command(term(), String.t(), keyword()) ::
              {:ok, %{output: String.t(), exit_code: integer(), truncated?: boolean()}}
              | {:error, term()}

  @callback environment_context(term()) :: map()

  @spec working_directory(term()) :: String.t()
  def working_directory(env), do: impl!(env).working_directory(env)

  @spec platform(term()) :: String.t()
  def platform(env), do: impl!(env).platform(env)

  @spec read_file(term(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def read_file(env, path), do: impl!(env).read_file(env, path)

  @spec write_file(term(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_file(env, path, content), do: impl!(env).write_file(env, path, content)

  @spec list_directory(term(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_directory(env, path), do: impl!(env).list_directory(env, path)

  @spec glob(term(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def glob(env, pattern), do: impl!(env).glob(env, pattern)

  @spec grep(term(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def grep(env, pattern, opts), do: impl!(env).grep(env, pattern, opts)

  @spec shell_command(term(), String.t(), keyword()) ::
          {:ok, %{output: String.t(), exit_code: integer(), truncated?: boolean()}}
          | {:error, term()}
  def shell_command(env, command, opts), do: impl!(env).shell_command(env, command, opts)

  @spec environment_context(term()) :: map()
  def environment_context(env), do: impl!(env).environment_context(env)

  @spec implementation?(term()) :: boolean()
  def implementation?(env) do
    module = impl(env)
    behaviours = if module, do: module.module_info(:attributes)[:behaviour] || [], else: []
    __MODULE__ in behaviours
  end

  defp impl(%module{}), do: module
  defp impl(_env), do: nil

  defp impl!(env) do
    if implementation?(env) do
      impl(env)
    else
      raise ArgumentError, "expected an ExecutionEnvironment implementation, got: #{inspect(env)}"
    end
  end
end
