defmodule AttractorEx.Agent.BuiltinTools do
  @moduledoc """
  Built-in coding-agent tools backed by an `ExecutionEnvironment`.

  The `:default` preset exposes a provider-neutral baseline toolset. Provider
  presets then layer provider-native tool names and argument shapes on top of
  the same execution environment so OpenAI, Anthropic, and Gemini sessions can
  stay closer to their upstream agent harnesses. Gemini's optional web tools can
  also be enabled for the `:gemini` preset.
  """

  alias AttractorEx.Agent.{ApplyPatch, ExecutionEnvironment, Tool}

  @type preset :: :openai | :anthropic | :gemini | :default

  @spec for_provider(preset(), keyword()) :: [Tool.t()]
  def for_provider(provider, opts \\ [])
      when provider in [:openai, :anthropic, :gemini, :default] and is_list(opts) do
    case provider do
      :default ->
        [
          read_file_tool(),
          write_file_tool(),
          list_directory_tool(),
          glob_tool(),
          grep_tool(),
          shell_command_tool(),
          spawn_agent_tool(),
          send_input_tool(),
          wait_tool(),
          close_agent_tool()
        ]

      :openai ->
        [
          read_file_tool(),
          apply_patch_tool(),
          write_file_tool(),
          shell_tool("shell", 10_000),
          grep_tool(),
          glob_tool(),
          spawn_agent_tool(),
          send_input_tool(),
          wait_tool(),
          close_agent_tool()
        ]

      :anthropic ->
        [
          read_file_tool(),
          write_file_tool(),
          edit_file_tool(),
          shell_tool("shell", 120_000),
          grep_tool(),
          glob_tool(),
          spawn_agent_tool(),
          send_input_tool(),
          wait_tool(),
          close_agent_tool()
        ]

      :gemini ->
        gemini_tools =
          [
            read_file_tool(),
            read_many_files_tool(),
            write_file_tool(),
            edit_file_tool(),
            shell_tool("shell", 10_000),
            grep_tool(),
            glob_tool(),
            list_dir_tool(),
            spawn_agent_tool(),
            send_input_tool(),
            wait_tool(),
            close_agent_tool()
          ]

        case gemini_web_tool_options(opts) do
          nil -> gemini_tools
          web_opts -> gemini_tools ++ [web_search_tool(web_opts), web_fetch_tool(web_opts)]
        end
    end
  end

  defp read_file_tool do
    %Tool{
      name: "read_file",
      description: "Read a file from the filesystem. Returns line-numbered content.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "file_path" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "offset" => %{"type" => "integer"},
          "limit" => %{"type" => "integer"}
        }
      },
      execute: fn args, env ->
        ensure_environment!(env)
        path = required_path(args)
        offset = Map.get(args, "offset", 1)
        limit = Map.get(args, "limit", 2_000)

        case ExecutionEnvironment.read_file(env, path) do
          {:ok, content} -> render_line_numbered_content(content, offset, limit)
          {:error, reason} -> raise "read_file failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp read_many_files_tool do
    %Tool{
      name: "read_many_files",
      description: "Read multiple files and return line-numbered content blocks.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "paths" => %{"type" => "array"},
          "offset" => %{"type" => "integer"},
          "limit" => %{"type" => "integer"}
        },
        "required" => ["paths"]
      },
      execute: fn %{"paths" => paths} = args, env ->
        ensure_environment!(env)
        offset = Map.get(args, "offset", 1)
        limit = Map.get(args, "limit", 2_000)

        paths
        |> Enum.map(fn path ->
          case ExecutionEnvironment.read_file(env, path) do
            {:ok, content} ->
              ["FILE #{path}", render_line_numbered_content(content, offset, limit)]

            {:error, reason} ->
              ["FILE #{path}", "ERROR #{inspect(reason)}"]
          end
        end)
        |> List.flatten()
        |> Enum.join("\n")
      end
    }
  end

  defp write_file_tool do
    %Tool{
      name: "write_file",
      description: "Write content to a file. Creates the file and parent directories if needed.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "file_path" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "content" => %{"type" => "string"}
        },
        "required" => ["content"]
      },
      execute: fn args, env ->
        ensure_environment!(env)
        path = required_path(args)
        content = Map.fetch!(args, "content")

        case ExecutionEnvironment.write_file(env, path, content) do
          :ok -> "Wrote #{path} (#{byte_size(content)} bytes)"
          {:error, reason} -> raise "write_file failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp edit_file_tool do
    %Tool{
      name: "edit_file",
      description: "Replace an exact string occurrence in a file.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "file_path" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "old_string" => %{"type" => "string"},
          "new_string" => %{"type" => "string"},
          "replace_all" => %{"type" => "boolean"}
        },
        "required" => ["old_string", "new_string"]
      },
      execute: fn args, env ->
        ensure_environment!(env)
        path = required_path(args)
        old_string = Map.fetch!(args, "old_string")
        new_string = Map.fetch!(args, "new_string")
        replace_all = Map.get(args, "replace_all", false)

        case ExecutionEnvironment.read_file(env, path) do
          {:ok, content} ->
            {updated, count} = replace_exact(content, old_string, new_string, replace_all)

            cond do
              count == 0 ->
                raise "edit_file failed: old_string not found"

              count > 1 and not replace_all ->
                raise "edit_file failed: old_string is not unique; provide more context"

              true ->
                case ExecutionEnvironment.write_file(env, path, updated) do
                  :ok ->
                    "Edited #{path} (#{count} replacement#{if count == 1, do: "", else: "s"})"

                  {:error, reason} ->
                    raise "edit_file failed: #{inspect(reason)}"
                end
            end

          {:error, reason} ->
            raise "edit_file failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp apply_patch_tool do
    %Tool{
      name: "apply_patch",
      description:
        "Apply code changes using the patch format. Supports creating, deleting, and modifying files in a single operation.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "patch" => %{"type" => "string"}
        },
        "required" => ["patch"]
      },
      execute: fn %{"patch" => patch}, env ->
        ensure_environment!(env)

        case ApplyPatch.apply(env, patch) do
          {:ok, operations} -> Jason.encode!(operations)
          {:error, reason} -> raise "apply_patch failed: #{reason}"
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

  defp list_dir_tool do
    %Tool{
      name: "list_dir",
      description: "List files and directories under a relative path.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "depth" => %{"type" => "integer"}
        }
      },
      execute: fn args, env ->
        ensure_environment!(env)
        path = Map.get(args, "path", ".")

        case ExecutionEnvironment.list_directory(env, path) do
          {:ok, entries} -> Jason.encode!(entries)
          {:error, reason} -> raise "list_dir failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp web_search_tool(opts) do
    %Tool{
      name: "web_search",
      description: "Search the web and return a compact list of result titles and URLs.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string"},
          "limit" => %{"type" => "integer"}
        },
        "required" => ["query"]
      },
      execute: fn %{"query" => query} = args, _env ->
        limit = normalize_positive_integer(Map.get(args, "limit", 5), 5)
        url = build_web_search_url(opts, query)
        body = request_web!(url, web_request_options(opts))

        body
        |> extract_search_results()
        |> Enum.take(limit)
        |> Jason.encode!()
      end
    }
  end

  defp web_fetch_tool(opts) do
    %Tool{
      name: "web_fetch",
      description: "Fetch a web page and return a bounded text summary of the response body.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string"},
          "max_bytes" => %{"type" => "integer"}
        },
        "required" => ["url"]
      },
      execute: fn %{"url" => url} = args, _env ->
        max_bytes = normalize_positive_integer(Map.get(args, "max_bytes", 20_000), 20_000)
        body = request_web!(url, web_request_options(opts))
        bounded_body = binary_part(body, 0, min(byte_size(body), max_bytes))

        %{
          url: url,
          truncated?: byte_size(body) > max_bytes,
          content: bounded_body
        }
        |> Jason.encode!()
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
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"}
        },
        "required" => ["pattern"]
      },
      execute: fn args, env ->
        ensure_environment!(env)
        pattern = Map.fetch!(args, "pattern")

        case ExecutionEnvironment.glob(env, prefix_pattern(Map.get(args, "path"), pattern)) do
          {:ok, matches} -> Jason.encode!(matches)
          {:error, reason} -> raise "glob failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp grep_tool do
    %Tool{
      name: "grep",
      description: "Search file contents using regex patterns.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "glob_filter" => %{"type" => "string"},
          "case_sensitive" => %{"type" => "boolean"},
          "case_insensitive" => %{"type" => "boolean"},
          "max_results" => %{"type" => "integer"}
        },
        "required" => ["pattern"]
      },
      execute: fn args, env ->
        ensure_environment!(env)

        options = [
          path: Map.get(args, "path", "."),
          case_sensitive:
            if(Map.get(args, "case_insensitive", false),
              do: false,
              else: Map.get(args, "case_sensitive", false)
            ),
          max_results: Map.get(args, "max_results", 200)
        ]

        case ExecutionEnvironment.grep(env, args["pattern"], options) do
          {:ok, matches} ->
            matches
            |> maybe_filter_matches(Map.get(args, "glob_filter"))
            |> Jason.encode!()

          {:error, reason} ->
            raise "grep failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp shell_command_tool do
    shell_tool("shell_command", 10_000)
  end

  defp shell_tool(name, default_timeout_ms) do
    %Tool{
      name: name,
      description: "Execute a shell command. Returns stdout, stderr, and exit code.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string"},
          "timeout_ms" => %{"type" => "integer"},
          "description" => %{"type" => "string"}
        },
        "required" => ["command"]
      },
      execute: fn args, env ->
        ensure_environment!(env)
        options = [timeout_ms: Map.get(args, "timeout_ms", default_timeout_ms)]

        case ExecutionEnvironment.shell_command(env, args["command"], options) do
          {:ok, %{output: output, exit_code: exit_code}} ->
            "exit_code=#{exit_code}\n#{output}"

          {:error, :timeout} ->
            raise "#{name} failed: timeout"

          {:error, reason} ->
            raise "#{name} failed: #{inspect(reason)}"
        end
      end
    }
  end

  defp spawn_agent_tool do
    %Tool{
      name: "spawn_agent",
      description: "Spawn a subagent to handle a scoped task autonomously.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "task" => %{"type" => "string"},
          "working_dir" => %{"type" => "string"},
          "model" => %{"type" => "string"},
          "max_turns" => %{"type" => "integer"}
        },
        "required" => ["task"]
      },
      target: :session,
      execute: fn args, session ->
        AttractorEx.Agent.Session.run_subagent_tool(session, "spawn_agent", args)
      end
    }
  end

  defp send_input_tool do
    %Tool{
      name: "send_input",
      description: "Send a message to a running subagent.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"},
          "message" => %{"type" => "string"}
        },
        "required" => ["agent_id", "message"]
      },
      target: :session,
      execute: fn args, session ->
        AttractorEx.Agent.Session.run_subagent_tool(session, "send_input", args)
      end
    }
  end

  defp wait_tool do
    %Tool{
      name: "wait",
      description: "Wait for a subagent to complete and return its result.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      },
      target: :session,
      execute: fn args, session ->
        AttractorEx.Agent.Session.run_subagent_tool(session, "wait", args)
      end
    }
  end

  defp close_agent_tool do
    %Tool{
      name: "close_agent",
      description: "Terminate a subagent.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "agent_id" => %{"type" => "string"}
        },
        "required" => ["agent_id"]
      },
      target: :session,
      execute: fn args, session ->
        AttractorEx.Agent.Session.run_subagent_tool(session, "close_agent", args)
      end
    }
  end

  defp ensure_environment!(env) do
    unless ExecutionEnvironment.implementation?(env) do
      raise ArgumentError, "tool requires an ExecutionEnvironment implementation"
    end
  end

  defp required_path(args) do
    case Map.get(args, "file_path") || Map.get(args, "path") do
      path when is_binary(path) and path != "" -> path
      _ -> raise KeyError, key: "file_path", term: args
    end
  end

  defp render_line_numbered_content(content, offset, limit) do
    start_line = normalize_positive_integer(offset, 1)
    max_lines = normalize_positive_integer(limit, 2_000)

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.drop(start_line - 1)
    |> Enum.take(max_lines)
    |> Enum.map_join("\n", fn {line, line_number} ->
      "#{line_number} | #{line}"
    end)
  end

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default

  defp replace_exact(content, old_string, new_string, replace_all) do
    count =
      content
      |> String.split(old_string)
      |> length()
      |> Kernel.-(1)
      |> max(0)

    updated =
      if count > 0 do
        if replace_all do
          String.replace(content, old_string, new_string)
        else
          String.replace(content, old_string, new_string, global: false)
        end
      else
        content
      end

    {updated, count}
  end

  defp prefix_pattern(nil, pattern), do: pattern
  defp prefix_pattern("", pattern), do: pattern
  defp prefix_pattern(path, pattern), do: Path.join(path, pattern)

  defp maybe_filter_matches(matches, nil), do: matches

  defp maybe_filter_matches(matches, glob_filter) do
    Enum.filter(matches, fn match ->
      wildcard_match?(match.path, glob_filter)
    end)
  end

  defp gemini_web_tool_options(opts) do
    case Keyword.get(opts, :web_tools, false) do
      false -> nil
      nil -> nil
      true -> []
      web_opts when is_list(web_opts) -> web_opts
    end
  end

  defp build_web_search_url(opts, query) do
    base_url = Keyword.get(opts, :search_url, "https://duckduckgo.com/html/")
    query_param = Keyword.get(opts, :search_query_param, "q")
    separator = if String.contains?(base_url, "?"), do: "&", else: "?"

    base_url <> separator <> URI.encode_query(%{query_param => query})
  end

  defp web_request_options(opts) do
    timeout_ms = normalize_positive_integer(Keyword.get(opts, :timeout_ms, 5_000), 5_000)

    [
      connect_options: [timeout: timeout_ms],
      receive_timeout: timeout_ms,
      headers: [{"user-agent", Keyword.get(opts, :user_agent, "AttractorEx/1.0")}]
    ]
  end

  defp request_web!(url, req_opts) do
    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        body
        |> to_string()
        |> String.trim()

      {:ok, %Req.Response{status: status, body: body}} ->
        raise "web request failed: HTTP #{status} #{inspect(body)}"

      {:error, reason} ->
        raise "web request failed: #{Exception.message(reason)}"
    end
  end

  defp extract_search_results(body) do
    Regex.scan(~r/<a[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/is, body, capture: :all_but_first)
    |> Enum.map(fn [url, title] ->
      %{
        "title" => clean_html_fragment(title),
        "url" => String.trim(url)
      }
    end)
    |> Enum.reject(fn result ->
      result["title"] == "" or result["url"] == ""
    end)
  end

  defp clean_html_fragment(fragment) do
    fragment
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp wildcard_match?(path, glob_filter) do
    glob_filter
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> String.replace("\\?", ".")
    |> then(&Regex.compile!("^" <> &1 <> "$"))
    |> Regex.match?(path)
  end
end
