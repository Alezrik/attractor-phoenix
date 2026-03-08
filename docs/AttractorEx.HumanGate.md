# `AttractorEx.HumanGate`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/human_gate.ex#L1)

Helper functions for building and matching `wait.human` choices.

This module converts outgoing edges into normalized selectable options and performs
tolerant matching against keys, labels, and destination node IDs.

# `choices_for`

Builds the available choices for a human-gate node from its outgoing edges.

# `match_choice`

Finds the first matching choice for a human answer token.

# `normalize_token`

Normalizes answer tokens for case-insensitive matching.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
