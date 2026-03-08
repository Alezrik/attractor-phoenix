defmodule AttractorExTest.ExecutionEnv do
  @moduledoc false

  @behaviour AttractorEx.Agent.ExecutionEnvironment

  defstruct mode: :ok

  @impl true
  def working_directory(_env), do: "/tmp/fake"

  @impl true
  def platform(_env), do: "test-platform"

  @impl true
  def read_file(%__MODULE__{mode: :read_error}, _path), do: {:error, :enoent}
  def read_file(_env, _path), do: {:ok, "fake-content"}

  @impl true
  def write_file(%__MODULE__{mode: :write_error}, _path, _content), do: {:error, :eperm}
  def write_file(_env, _path, _content), do: :ok

  @impl true
  def list_directory(%__MODULE__{mode: :list_error}, _path), do: {:error, :enoent}

  def list_directory(_env, _path),
    do: {:ok, [%{name: "file.txt", path: "file.txt", type: "file"}]}

  @impl true
  def glob(%__MODULE__{mode: :glob_error}, _pattern), do: {:error, :bad_pattern}
  def glob(_env, _pattern), do: {:ok, ["file.txt"]}

  @impl true
  def grep(%__MODULE__{mode: :grep_error}, _pattern, _opts), do: {:error, :io_failure}
  def grep(_env, _pattern, _opts), do: {:ok, [%{path: "file.txt", line_number: 1, line: "match"}]}

  @impl true
  def shell_command(%__MODULE__{mode: :shell_timeout}, _command, _opts), do: {:error, :timeout}
  def shell_command(%__MODULE__{mode: :shell_error}, _command, _opts), do: {:error, :failed}

  def shell_command(_env, _command, _opts) do
    {:ok, %{output: "ok", exit_code: 0, truncated?: false}}
  end

  @impl true
  def environment_context(_env), do: %{test: true}
end
