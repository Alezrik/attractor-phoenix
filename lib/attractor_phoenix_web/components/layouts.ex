defmodule AttractorPhoenixWeb.Layouts do
  @moduledoc """
  Shared layout primitives for the application shell.
  """
  use AttractorPhoenixWeb, :html

  alias AttractorPhoenixWeb.OperatorRunData

  embed_templates "layouts/*"

  @doc """
  Renders the shared product shell around each LiveView.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: nil, doc: "the current request path"
  attr :page_title, :string, default: nil
  attr :page_kicker, :string, default: nil
  attr :page_subtitle, :string, default: nil

  slot :actions
  slot :status
  slot :shell_meta
  slot :mobile_nav_footer
  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:nav_items, nav_items())
      |> assign(:shell_title, assigns.page_title || page_title_from_path(assigns.current_path))
      |> assign(:shell_kicker, assigns.page_kicker || section_label(assigns.current_path))
      |> assign(
        :shell_subtitle,
        assigns.page_subtitle || default_subtitle(assigns.current_path, assigns.page_title)
      )

    ~H"""
    <div class="app-shell">
      <header class="shell-header">
        <div class="shell-header-inner">
          <div class="shell-brand-row">
            <.link navigate={~p"/"} class="shell-brand" id="shell-brand">
              <span class="shell-brand-mark">
                <span class="shell-brand-mark-core"></span>
              </span>
              <span>
                <span class="shell-brand-name">Attractor Phoenix</span>
                <span class="shell-brand-tagline">workflow operator studio</span>
              </span>
            </.link>

            <nav class="shell-nav hidden xl:flex" id="top-nav" aria-label="Primary">
              <.nav_link
                :for={item <- @nav_items}
                current_path={@current_path}
                href={item.href}
                label={item.label}
                match={item.match}
              />
            </nav>
          </div>

          <div class="shell-command-bar">
            <div class="shell-command-chip">
              <.icon name="hero-command-line" class="size-4" />
              <span>Operator shell</span>
            </div>
            <div class="hidden md:flex items-center gap-2">
              {render_slot(@shell_meta)}
            </div>
            <.theme_toggle />
          </div>
        </div>
      </header>

      <main class="shell-main">
        <div class="shell-main-inner">
          <section class="shell-page-header">
            <div class="shell-page-identity">
              <p :if={@shell_kicker} class="shell-kicker">{@shell_kicker}</p>
              <div class="space-y-3">
                <h1 class="shell-page-title">{@shell_title}</h1>
                <p :if={@shell_subtitle} class="shell-page-subtitle">{@shell_subtitle}</p>
              </div>
            </div>

            <div class="shell-header-side">
              <div :if={@actions != []} id="shell-actions" class="shell-actions">
                {render_slot(@actions)}
              </div>

              <div id="shell-status-rail" class="shell-status-rail">
                <div :if={@status != []} class="shell-status-list" role="list">
                  {render_slot(@status)}
                </div>
                <div :if={@status == []} class="shell-status-empty">
                  Route context updates and page telemetry land here.
                </div>
              </div>
            </div>
          </section>

          <details class="shell-mobile-nav xl:hidden">
            <summary class="shell-mobile-nav-toggle">
              <span class="inline-flex items-center gap-2">
                <.icon name="hero-squares-2x2" class="size-4" />
                <span>Navigate</span>
              </span>
              <.icon name="hero-chevron-down-mini" class="size-4 shell-mobile-chevron" />
            </summary>
            <nav class="shell-mobile-nav-panel" aria-label="Primary mobile">
              <.nav_link
                :for={item <- @nav_items}
                current_path={@current_path}
                href={item.href}
                label={item.label}
                match={item.match}
                mobile={true}
              />
              <div :if={@mobile_nav_footer != []} class="shell-mobile-nav-footer">
                {render_slot(@mobile_nav_footer)}
              </div>
            </nav>
          </details>

          <div class="shell-page-body">
            {render_slot(@inner_block)}
          </div>
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :current_path, :string, default: nil
  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :match, :atom, values: [:exact, :prefix], default: :exact
  attr :mobile, :boolean, default: false

  defp nav_link(assigns) do
    active? =
      case assigns.match do
        :prefix -> String.starts_with?(assigns.current_path || "", assigns.href)
        :exact -> assigns.current_path == assigns.href
      end

    assigns =
      assign(assigns,
        classes: [
          if(assigns.mobile, do: "shell-nav-link-mobile", else: "shell-nav-link"),
          if(active?, do: "shell-nav-link-active", else: "shell-nav-link-idle")
        ]
      )

    ~H"""
    <.link navigate={@href} class={@classes}>
      {@label}
    </.link>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="flash-stack" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Standard status card used inside the shell status rail.
  """
  slot :inner_block, required: true

  def shell_status_item(assigns) do
    ~H"""
    <div class="shell-status-card" role="listitem">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Theme toggle aligned with the shared product shell.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="theme-toggle">
      <div class="theme-toggle-indicator"></div>

      <button
        type="button"
        class="theme-toggle-button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="theme-toggle-button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="theme-toggle-button"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  def route_connection_tone(state) do
    case state do
      :live -> "shell-status-value shell-status-value-success"
      :stale -> "shell-status-value shell-status-value-warning"
      :reconnecting -> "shell-status-value shell-status-value-warning"
      :idle -> "shell-status-value shell-status-value-muted"
      _ -> "shell-status-value shell-status-value-muted"
    end
  end

  def route_connection_label(state), do: OperatorRunData.default_connection_label(state)

  def shell_timestamp(nil), do: "Waiting for first refresh"

  def shell_timestamp(%DateTime{} = value) do
    Calendar.strftime(value, "%H:%M:%S UTC")
  end

  defp nav_items do
    [
      %{href: ~p"/", label: "Dashboard", match: :exact},
      %{href: ~p"/benchmark", label: "Benchmark", match: :prefix},
      %{href: ~p"/create", label: "Create", match: :exact},
      %{href: ~p"/builder", label: "Builder", match: :prefix},
      %{href: ~p"/setup", label: "Setup", match: :prefix},
      %{href: ~p"/library", label: "Library", match: :prefix}
    ]
  end

  defp section_label(path) do
    cond do
      path == ~p"/" -> "Operator Control"
      path == ~p"/benchmark" -> "Leadership Contract"
      path == ~p"/builder" -> "Graph Studio"
      path == ~p"/create" -> "AI Drafting"
      path == ~p"/setup" -> "Provider Control"
      is_binary(path) and String.starts_with?(path, "/library") -> "Library System"
      is_binary(path) and String.starts_with?(path, "/runs/") -> "Run Operations"
      true -> "Workspace"
    end
  end

  defp page_title_from_path(path) do
    cond do
      path == ~p"/" -> "Operator Dashboard"
      path == ~p"/benchmark" -> "Product Benchmark"
      path == ~p"/builder" -> "Pipeline Builder"
      path == ~p"/create" -> "Create Pipeline"
      path == ~p"/setup" -> "Provider Setup"
      is_binary(path) and String.starts_with?(path, "/library") -> "Pipeline Library"
      is_binary(path) and String.starts_with?(path, "/runs/") -> "Run Workspace"
      true -> "Workspace"
    end
  end

  defp default_subtitle(path, page_title) do
    cond do
      path == ~p"/" ->
        "Live queue health, failure pressure, and human-gate load in one product shell."

      path == ~p"/benchmark" ->
        "Translate repo ambition into a visible scorecard, evidence ledger, and leadership bar."

      path == ~p"/builder" ->
        "Author, inspect, and execute runtime-backed workflow graphs without losing system context."

      path == ~p"/create" ->
        "Draft a runnable graph from English, then move directly into the canonical builder."

      path == ~p"/setup" ->
        "Configure provider credentials, discover models, and keep default generation settings sane."

      is_binary(path) and String.starts_with?(path, "/library") ->
        "Manage reusable graph presets that route cleanly back into the builder and operator surfaces."

      is_binary(path) and String.starts_with?(path, "/runs/") and is_binary(page_title) ->
        "#{page_title} stays inside the same shell, with route actions and context chips above the page."

      true ->
        nil
    end
  end
end
