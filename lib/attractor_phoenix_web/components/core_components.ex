defmodule AttractorPhoenixWeb.CoreComponents do
  @moduledoc """
  Shared UI primitives for the product shell.
  """
  use Phoenix.Component
  use Gettext, backend: AttractorPhoenixWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> "flash-#{assigns.kind}" end)
      |> assign(
        :tone,
        case assigns.kind do
          :info -> "ui-flash-card ui-flash-info"
          :error -> "ui-flash-card ui-flash-error"
        end
      )

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="ui-flash"
      {@rest}
    >
      <div class={@tone}>
        <div class="ui-flash-icon">
          <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
          <.icon :if={@kind == :error} name="hero-exclamation-triangle" class="size-5 shrink-0" />
        </div>
        <div class="min-w-0 flex-1">
          <p :if={@title} class="ui-flash-title">{@title}</p>
          <p class="ui-flash-message">{msg}</p>
        </div>
        <button type="button" class="ui-flash-close" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary secondary ghost danger)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "ui-button ui-button-primary",
      "secondary" => "ui-button ui-button-secondary",
      "ghost" => "ui-button ui-button-ghost",
      "danger" => "ui-button ui-button-danger",
      nil => "ui-button ui-button-secondary"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        [Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="ui-field">
      <label class="ui-checkbox-wrap">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "ui-checkbox"}
          {@rest}
        />
        <span class="ui-checkbox-label">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="ui-field">
      <label :if={@label} class="ui-label" for={@id}>{@label}</label>
      <div class="ui-input-shell">
        <select
          id={@id}
          name={@name}
          class={[
            @class || "ui-input ui-select",
            @errors != [] && (@error_class || "ui-input-error")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="ui-field">
      <label :if={@label} class="ui-label" for={@id}>{@label}</label>
      <div class="ui-input-shell">
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "ui-input ui-textarea",
            @errors != [] && (@error_class || "ui-input-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="ui-field">
      <label :if={@label} class="ui-label" for={@id}>{@label}</label>
      <div class="ui-input-shell">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "ui-input",
            @errors != [] && (@error_class || "ui-input-error")
          ]}
          {@rest}
        />
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  slot :inner_block, required: true

  defp error(assigns) do
    ~H"""
    <p class="ui-error">
      <.icon name="hero-exclamation-circle" class="size-4" />
      <span>{render_slot(@inner_block)}</span>
    </p>
    """
  end

  @doc """
  Renders a compact inline error surface.
  """
  attr :id, :string, required: true
  attr :title, :string, default: "Attention"
  attr :message, :string, required: true

  def inline_error(assigns) do
    ~H"""
    <div id={@id} class="ui-inline-error" role="alert">
      <div class="ui-inline-error-icon">
        <.icon name="hero-exclamation-triangle" class="size-5" />
      </div>
      <div class="min-w-0 flex-1">
        <p class="ui-inline-error-title">{@title}</p>
        <p class="ui-inline-error-message">{@message}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a standard empty state.
  """
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :icon, :string, default: "hero-inbox-stack"
  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class="ui-empty-state">
      <div class="ui-empty-state-icon">
        <.icon name={@icon} class="size-6" />
      </div>
      <div class="space-y-2">
        <p class="ui-empty-state-title">{@title}</p>
        <p class="ui-empty-state-message">{@message}</p>
      </div>
      <div :if={@actions != []} class="ui-empty-state-actions">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a lightweight loading skeleton block.
  """
  attr :class, :string, default: nil

  def skeleton(assigns) do
    ~H"""
    <div class={["ui-skeleton", @class]} aria-hidden="true"></div>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "ui-section-header"]}>
      <div>
        <h2 class="ui-section-title">{render_slot(@inner_block)}</h2>
        <p :if={@subtitle != []} class="ui-section-subtitle">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with shared styling.
  """
  attr :id, :string, required: true
  attr :rows, :any, required: true
  attr :row_id, :any, default: nil
  attr :row_click, :any, default: nil

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="ui-table-shell">
      <table class="ui-table">
        <thead>
          <tr>
            <th :for={col <- @col}>{col[:label]}</th>
            <th :if={@action != []}>
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={@row_click && "cursor-pointer"}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="ui-table-actions">
              <div class="flex gap-3">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="ui-list">
      <div :for={item <- @item} class="ui-list-row">
        <div class="ui-list-title">{item.title}</div>
        <div class="ui-list-value">{render_slot(item)}</div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a Heroicon.
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(AttractorPhoenixWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(AttractorPhoenixWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
