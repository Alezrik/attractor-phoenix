# `AttractorEx.HTTP`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http.ex#L1)

Convenience entry point for starting and stopping the AttractorEx HTTP service.

The service is composed of `AttractorEx.HTTP.Manager`, a `Registry`, and a Bandit
server running `AttractorEx.HTTP.Router`.

# `start_server`

Starts the HTTP manager, registry, and Bandit server.

# `stop_server`

Stops a running HTTP server process or named server.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
