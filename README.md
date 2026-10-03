# jevgrep-harness

An agent-harness layer for [jevgrep](https://github.com/dzhng/jevgrep) (`jg`) in
[opencode](https://opencode.ai): a fail-fast CLI wrapper, cost-routing rules, and
a repeatable benchmark suite. Goal: **faster and more accurate code discovery at
lower total agent cost** by routing each query to the cheapest tool that can
answer it.

## The routing idea

Coding-agent discovery cost is not grep time — it is model turns and irrelevant
context. Two tool tiers cover the two query classes:

| Tier | Query class | Tool | Cost |
|---|---|---|---|
| 0 — exact | known symbol / filename / string | `grep`, opencode `lsp` tool (`workspaceSymbol` first) | free, local |
| 1 — behavioral | "how does X work", "where is Y handled" | `jga` (jevgrep semantic search) | ~$0.001–0.01/search, saves multi-turn grep/read loops |

Exact-string questions must never escalate; behavioral questions must not
degrade into grep→read→skim loops (cap: two rounds).

## Components

- **`bin/jga`** — wrapper around `jg`:
  - exits 2 with a stderr hint when credentials are missing, so the calling
    agent falls back to Tier 0 instead of burning a search on an auth error
  - refuses over-broad roots (`$HOME`, `/`) — a home-dir sweep measured
    62k eligible files / 20.9 GiB
  - runs the free `jg files` pre-flight and warns above 8k files
  - logs every search (duration, requests, incomplete flag, flood size, top-1)
    as TSV to `~/.local/share/opencode/jg-usage.tsv` for cost A/B
  - keeps stdout pure `jg` output; all telemetry goes to stderr
- **`AGENTS.md`** — the routing rules; drop this into `~/.config/opencode/AGENTS.md`
  (or your project root) so the agent applies the tiers automatically
- **`tests/run-tests.sh`** — offline checks (install, credentials, fail-fast,
  free pre-flight), a Tier-0 speed control, and behavioral queries with
  hand-verified ground truth asserting top-1 file, complete discovery, and
  latency. One informational big-root probe documents the known failure mode.

## Install

```sh
npm install -g @dzhng/jevgrep   # requires Node 22+
jg auth                          # choose provider, enter key
cp bin/jga ~/.local/bin/jga && chmod +x ~/.local/bin/jga
# merge AGENTS.md into your opencode global or project instructions
npx skills add dzhng/jevgrep --skill jevgrep   # optional: the upstream skill
```

## Measured results (2026-10-03, single-repo benchmark, n=3 ground-truth queries)

| Check | Result |
|---|---|
| Behavioral top-1 precision | 3/3 correct (`lsp/manager.py`, `file_operations_lint.py`, `mcp_tool_lifecycle.py`) |
| Latency (narrow roots, 300–320 files) | 3–17s cold; 3–4s with jg's local eval cache |
| Tier-0 control (grep exact symbol) | 0.24s, free |
| Repo-root query (14k files) | incomplete discovery + 299-file flood + 272s → narrowed-root rule exists for a reason |
| Jev spend, full day of testing | ~2.51M tokens ≈ **$0.11** at $0.042/1M |

Single-run observations, one repo, known-layout codebase — they validate wiring
and ranking, not upstream's −28.6% SWE-bench cost claim. The true A/B (same
task, agent with vs. without Tier 1 available) is the metric that matters.

## Adapting the benchmark

`BENCH_REPO=... ./tests/run-tests.sh` — point it at any repo whose behavioral
answers you have verified by hand, then edit the three `bench()` calls with
your own question → expected-top-1 pairs. Keep required vs informational
assertions separated: the suite must stay honest about what it proves.

## License

MIT
