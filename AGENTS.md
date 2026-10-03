# Code discovery routing

Choose the cheapest tool that answers the query. Default tier costs nothing; escalation costs Jev API calls.

## Tier 0 — exact lookups (free, local, default)

- Known symbol, filename, or literal string: `grep` first, then `read` the hit.
- Symbol questions ("where is X defined/called", "who implements this"): use the `lsp` tool.
  - Prefer `workspaceSymbol` with a query — it needs no line/character and beats grep for definitions.
  - Use positional ops (`goToDefinition`, `findReferences`, `hover`, `incomingCalls`, `outgoingCalls`) once grep/read gave you a location (line/character are 1-based).
  - If the `lsp` tool errors ("No LSP server available"), fall back to grep — do not retry.
- Do not run grep→read→skim loops more than twice on the same question; escalate instead.

## Tier 1 — behavioral discovery (jevgrep `jg`)

Use when the question is about behavior, flow, or architecture and you cannot name the symbol: "how are X and Y connected", "where is Z handled", "what implements <behavior>".

- Invoke: `jga "<natural-language question>" [root]` — a wrapper that pre-flights the root, refuses over-broad ones, and logs usage. See the `jevgrep` skill for output semantics.
- Searches take 30–60s; pass a generous bash timeout (180000+ ms) or run in background and wait — do not fire a second search to "recover" the first.
- Prefer the narrowest plausible root (a subdirectory, not the repo root) when the question's scope is known; a 10k+-file root can exhaust its request budget in the wrong folders and return irrelevant leads.
- Do not pass `--max-requests` below ~500; low caps caused incomplete discovery in testing. If output says "discovery incomplete", narrow the root or rerun with the default budget.
- If the result floods with locations-only files, read only files labeled "implementation" first, then use grep/reads for the rest — do not read every lead.
- If you don't know the layout, run `jg files [root]` first; narrow with `--exclude` for generated/vendor dirs.
- Requires `jg` auth; `jga` exits 2 with a stderr hint when credentials are missing — say so and stay on Tier 0, do not block the task.
- Never use `jg`/`jga` for exact strings, filenames, or symbol definitions — that is Tier 0's job.
