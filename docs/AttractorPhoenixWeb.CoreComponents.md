# `AttractorPhoenixWeb.CoreComponents`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_phoenix_web/components/core_components.ex#L1)

Shared UI primitives for the product shell.

# `button`

Renders a button with navigation support.

## Attributes

* `class` (`:any`)
* `variant` (`:string`) - Must be one of `"primary"`, `"secondary"`, `"ghost"`, or `"danger"`.
* Global attributes are accepted. Supports all globals plus: `["href", "navigate", "patch", "method", "download", "name", "value", "disabled"]`.
## Slots

* `inner_block` (required)

# `empty_state`

Renders a standard empty state.

## Attributes

* `id` (`:string`) - Defaults to `nil`.
* `title` (`:string`) (required)
* `message` (`:string`) (required)
* `icon` (`:string`) - Defaults to `"hero-inbox-stack"`.
## Slots

* `actions`

# `flash`

Renders flash notices.

## Attributes

* `id` (`:string`) - the optional id of flash container.
* `flash` (`:map`) - the map of flash messages to display. Defaults to `%{}`.
* `title` (`:string`) - Defaults to `nil`.
* `kind` (`:atom`) - used for styling and flash lookup. Must be one of `:info`, or `:error`.
* Global attributes are accepted. the arbitrary HTML attributes to add to the flash container.
## Slots

* `inner_block` - the optional inner block that renders the flash message.

# `header`

Renders a header with title.

## Slots

* `inner_block` (required)
* `subtitle`
* `actions`

# `hide`

# `icon`

Renders a Heroicon.

## Attributes

* `name` (`:string`) (required)
* `class` (`:any`) - Defaults to `"size-4"`.

# `inline_error`

Renders a compact inline error surface.

## Attributes

* `id` (`:string`) (required)
* `title` (`:string`) - Defaults to `"Attention"`.
* `message` (`:string`) (required)

# `input`

Renders an input with label and error messages.

## Attributes

* `id` (`:any`) - Defaults to `nil`.
* `name` (`:any`)
* `label` (`:string`) - Defaults to `nil`.
* `value` (`:any`)
* `type` (`:string`) - Defaults to `"text"`. Must be one of `"checkbox"`, `"color"`, `"date"`, `"datetime-local"`, `"email"`, `"file"`, `"month"`, `"number"`, `"password"`, `"search"`, `"select"`, `"tel"`, `"text"`, `"textarea"`, `"time"`, `"url"`, `"week"`, or `"hidden"`.
* `field` (`Phoenix.HTML.FormField`) - a form field struct retrieved from the form, for example: @form[:email].
* `errors` (`:list`) - Defaults to `[]`.
* `checked` (`:boolean`) - the checked flag for checkbox inputs.
* `prompt` (`:string`) - the prompt for select inputs. Defaults to `nil`.
* `options` (`:list`) - the options to pass to Phoenix.HTML.Form.options_for_select/2.
* `multiple` (`:boolean`) - the multiple flag for select inputs. Defaults to `false`.
* `class` (`:any`) - the input class to use over defaults. Defaults to `nil`.
* `error_class` (`:any`) - the input error class to use over defaults. Defaults to `nil`.
* Global attributes are accepted. Supports all globals plus: `["accept", "autocomplete", "capture", "cols", "disabled", "form", "list", "max", "maxlength", "min", "minlength", "multiple", "pattern", "placeholder", "readonly", "required", "rows", "size", "step"]`.

# `list`

Renders a data list.

## Slots

* `item` (required) - Accepts attributes:

  * `title` (`:string`) (required)

# `show`

# `skeleton`

Renders a lightweight loading skeleton block.

## Attributes

* `class` (`:string`) - Defaults to `nil`.

# `table`

Renders a table with shared styling.

## Attributes

* `id` (`:string`) (required)
* `rows` (`:any`) (required)
* `row_id` (`:any`) - Defaults to `nil`.
* `row_click` (`:any`) - Defaults to `nil`.
* `row_item` (`:any`) - the function for mapping each row before calling the :col and :action slots. Defaults to `&Function.identity/1`.
## Slots

* `col` (required) - Accepts attributes:

  * `label` (`:string`)
* `action`

# `translate_error`

Translates an error message using gettext.

# `translate_errors`

Translates the errors for a field from a keyword list of errors.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
