# `AttractorPhoenixWeb.Layouts`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_phoenix_web/components/layouts.ex#L1)

Shared layout primitives for the application shell.

# `app`

Renders the shared product shell around each LiveView.

## Attributes

* `flash` (`:map`) (required) - the map of flash messages.
* `current_scope` (`:map`) - the current [scope](https://hexdocs.pm/phoenix/scopes.html). Defaults to `nil`.
* `current_path` (`:string`) - the current request path. Defaults to `nil`.
* `page_title` (`:string`) - Defaults to `nil`.
* `page_kicker` (`:string`) - Defaults to `nil`.
* `page_subtitle` (`:string`) - Defaults to `nil`.
## Slots

* `actions`
* `status`
* `shell_meta`
* `mobile_nav_footer`
* `inner_block` (required)

# `flash_group`

## Attributes

* `flash` (`:map`) (required) - the map of flash messages.
* `id` (`:string`) - the optional id of flash container. Defaults to `"flash-group"`.

# `root`

# `route_connection_label`

# `route_connection_tone`

# `shell_status_item`

Standard status card used inside the shell status rail.

## Slots

* `inner_block` (required)

# `shell_timestamp`

# `theme_toggle`

Theme toggle aligned with the shared product shell.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
