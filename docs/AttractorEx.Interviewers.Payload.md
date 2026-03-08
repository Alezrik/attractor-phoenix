# `AttractorEx.Interviewers.Payload`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/interviewer_payload.ex#L1)

Shared question and answer normalization for interviewer adapters.

This module keeps console, queue, callback, recording, and HTTP interviewers on the
same wire format so `wait.human` behavior stays consistent across transports.

# `answer_payload`

Builds a structured answer payload including matched options.

# `extract_answer`

Extracts the answer field from common structured answer payload shapes.

# `input_mode`

Returns the preferred input mode for the normalized question.

# `message`

Extracts a displayable message from an interviewer payload.

# `multiple_choice?`

Returns whether a node is configured for multi-select input.

# `normalize_choice`

Normalizes a single choice map into the shared interviewer shape.

# `normalize_multiple_answer`

Normalizes an answer for multi-select questions.

# `normalize_single_answer`

Normalizes an answer for single-select questions.

# `normalize_token`

Normalizes arbitrary answer values into comparable tokens.

# `parse_console_input`

Parses console input, decoding JSON objects and arrays when present.

# `question`

Builds the normalized question payload for a human-gate node.

# `question_type`

Infers the interviewer question type from node metadata and choice shape.

# `required?`

Returns whether a human answer is required for the node.

# `timeout_ms`

Normalizes timeout values such as `30s`, `5m`, or `1d` into milliseconds.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
