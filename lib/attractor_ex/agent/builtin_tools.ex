defmodule AttractorEx.Agent.BuiltinTools do
  @moduledoc """
  Built-in coding-agent tools backed by an `ExecutionEnvironment`.

  These tools provide a provider-neutral baseline toolset that can be attached
  to provider profiles such as OpenAI, Anthropic, and Gemini.
  """

  alias AttractorEx.Agent.{ExecutionEnvironment, Tool}

  @type preset :: :openai | :anthropic | :gemini | :default

  @spec for_provider(preset()) :: [Tool.t()]
  def for_provider(provider) when provider in [:openai, :anthropic, :gemini, :default] do
    base_tools = [
      read_file_tool(),
      write_file_tool(),
      list_directory_tool(),
      glob_tool(),
      grep_tool(),
      shell_command_tool()
    ]

    case provider do
      :gemini -> base_tools
      :anthropic -> base_tools
      :openai -> base_tools
      :default -> base_tools
    end
  end

  defp read_file_tool do
    %Tool{
      name: "read_file",
      description: "Read a UTF-8 text file from the execution environment.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"}
        },
        "required" => ["path"]
      },
      execute: fn %{"path" => path}, env ->
        ensure_environment!(env)

        case ExecutionEnvironment.read_file(env, path) do
          {:ok, content} -> content
          {:error, reason} -> raise "read_file failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp write_file_tool do
    %Tool{
      name: "write_file",
      description:
        "Write a UTF-8 text file in the execution environment, creating parent directories when needed.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "content" => %{"type" => "string"}
        },
        "required" => ["path", "content"]
      },
      execute: fn %{"path" => path, "content" => content}, env ->
        ensure_environment!(env)

        case ExecutionEnvironment.write_file(env, path, content) do
          :ok -> "Wrote #{path}"
          {:error, reason} -> raise "write_file failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp list_directory_tool do
    %Tool{
      name: "list_directory",
      description: "List files and directories under a relative path.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"}
        }
      },
      execute: fn args, env ->
        ensure_environment!(env)
        path = Map.get(args, "path", ".")

        case ExecutionEnvironment.list_directory(env, path) do
          {:ok, entries} -> Jason.encode!(entries)
          {:error, reason} -> raise "list_directory failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp glob_tool do
    %Tool{
      name: "glob",
      description: "Expand a filesystem glob pattern relative to the working directory.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"}
        },
        "required" => ["pattern"]
      },
      execute: fn %{"pattern" => pattern}, env ->
        ensure_environment!(env)

        case ExecutionEnvironment.glob(env, pattern) do
          {:ok, matches} -> Jason.encode!(matches)
          {:error, reason} -> raise "glob failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp grep_tool do
    %Tool{
      name: "grep",
      description: "Search for text in files under the working directory.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "case_sensitive" => %{"type" => "boolean"},
          "max_results" => %{"type" => "integer"}
        },
        "required" => ["pattern"]
      },
      execute: fn args, env ->
        ensure_environment!(env)

        options =
          [
            path: Map.get(args, "path", "."),
            case_sensitive: Map.get(args, "case_sensitive", false),
            max_results: Map.get(args, "max_results", 200)
          ]

        case ExecutionEnvironment.grep(env, args["pattern"], options) do
          {:ok, matches} -> Jason.encode!(matches)
          {:error, reason} -> raise "grep failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp shell_command_tool do
    %Tool{
      name: "shell_command",
      description: "Execute a shell command in the working directory.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string"},
          "timeout_ms" => %{"type" => "integer"}
        },
        "required" => ["command"]
      },
      execute: fn args, env ->
        ensure_environment!(env)
        options = [timeout_ms: Map.get(args, "timeout_ms", 10_000)]

        case ExecutionEnvironment.shell_command(env, args["command"], options) do
          {:ok, %{output: output, exit_code: exit_code}} ->
            "exit_code=#{exit_code}\n#{output}"

          {:error, :timeout} ->
            raise "shell_command failed: timeout"

          {:error, reason} ->
            raise "shell_command failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp ensure_environment!(env) do
    unless ExecutionEnvironment.implementation?(env) do
      raise ArgumentError, "tool requires an ExecutionEnvironment implementation"
    end
  end
end
