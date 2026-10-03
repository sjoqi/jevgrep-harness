#!/bin/sh
# Benchmark + regression suite for the jevgrep harness (jga wrapper + routing rules).
#
# Ground truth comes from manual code-reading of ~/.hermes/hermes-agent (verified
# during the 2026-10-03 prototype session). Required tests fail the suite;
# informational tests report but never fail.
#
# Usage: run-tests.sh [--skip-info]    Searches cost ~$0.001-0.01 each (TypeSafe Jev).

set -u
# Benchmark corpus: any repo whose behavioral ground truth you have verified by
# hand. Adapt the three bench() calls below to your repo's known answers.
REPO="${BENCH_REPO:-$HOME/.hermes/hermes-agent}"
JGA="${JGA_BIN:-$HOME/.local/bin/jga}"
PASS=0; FAIL=0; INFO=0

ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
note() { echo "INFO: $1"; INFO=$((INFO+1)); }

# --- T0: static checks (no network) -----------------------------------------
command -v jg >/dev/null && ok "jg installed ($(jg --version))" || bad "jg not installed"
[ -e "$HOME/.config/jevgrep" ] && ok "credentials present" || bad "credentials missing"
[ -x "$JGA" ] && ok "wrapper executable" || bad "wrapper missing/not executable"
grep -q "Tier 1" "$HOME/.config/opencode/AGENTS.md" 2>/dev/null && ok "routing rules installed" || bad "routing rules missing"

# --- T1: free pre-flight makes no provider requests --------------------------
OUT="$(jg files "$REPO/agent" 2>&1)"
case "$OUT" in
  *"No provider requests"*) ok "jg files pre-flight is offline";;
  *) bad "jg files made provider requests or failed: $OUT";;
esac

# --- T2: wrapper fail-fast without credentials -------------------------------
FAKE_HOME="$(mktemp -d)"
OUT="$(HOME="$FAKE_HOME" "$JGA" "test query" "$REPO/agent" 2>&1; echo "rc=$?")"
rm -rf "$FAKE_HOME"
case "$OUT" in
  *"rc=2"*) ok "wrapper fails fast (exit 2) without credentials";;
  *) bad "wrapper did not fail fast: $OUT";;
esac

# --- T3: Tier-0 control — exact symbol via grep must stay fast ---------------
S="$(date +%s)"
grep -rql "_lsp_will_handle" "$REPO/tools" >/dev/null 2>&1
D=$(( $(date +%s) - S ))
[ "$D" -lt 2 ] && ok "grep exact-symbol control ${D}s" || bad "grep control slow: ${D}s"

# --- Behavioral queries against known ground truth (required) ----------------
# Runs one search and asserts: top-1 file matches expectation, discovery complete,
# wall time under 120s. Args: name, root, expected-top1, question.
bench() {
  NAME="$1"; ROOT="$2"; EXPECT="$3"; QUESTION="$4"
  S="$(date +%s)"
  STDOUT="$("$JGA" "$QUESTION" "$ROOT" 2>/dev/null)"; RC=$?
  D=$(( $(date +%s) - S ))
  TOP1="$(printf '%s\n' "$STDOUT" | grep -o '^- "[^"]*"' | head -1 | sed 's/^- "//;s/"$//')"
  INC="$(printf '%s\n' "$STDOUT" | grep -c 'discovery incomplete')"
  [ "$RC" -eq 0 ] || { bad "$NAME exited rc=$RC in ${D}s"; return; }
  [ "$INC" -eq 0 ] || { bad "$NAME reported discovery incomplete (${D}s)"; return; }
  [ "$D" -lt 120 ] || { bad "$NAME too slow: ${D}s"; return; }
  if [ "$TOP1" = "$EXPECT" ]; then
    ok "$NAME top1=$TOP1 ${D}s"
  else
    bad "$NAME top1=$TOP1 expected=$EXPECT (${D}s)"
  fi
}

bench "lsp-lifecycle" "$REPO/agent" "lsp/manager.py" \
  "How are LSP language server clients started, reused, and torn down across workspaces?"
bench "lint-tier-handoff" "$REPO/tools" "file_operations_lint.py" \
  "How does the post-write lint tier decide between shell linters and LSP diagnostics?"
bench "mcp-spawn-kill" "$REPO/tools" "mcp_tool_lifecycle.py" \
  "How are MCP server child processes spawned and force-killed, including cleanup of non-MCP children?"

# --- T4: big-root behavior (informational — documents the known failure mode) -
if [ "${1:-}" = "--skip-info" ]; then
  note "big-root probe skipped"
else
  S="$(date +%s)"
  STDOUT="$("$JGA" "How are sessions stored and full-text searched in sqlite?" "$REPO" 2>/dev/null)"
  D=$(( $(date +%s) - S ))
  TOP1="$(printf '%s\n' "$STDOUT" | grep -o '^- "[^"]*"' | head -1 | sed 's/^- "//;s/"$//')"
  case "$STDOUT" in
    *"discovery incomplete"*) note "big-root (${D}s) incomplete as expected; top1=${TOP1:-none} — use narrowed roots";;
    *) note "big-root (${D}s) completed; top1=${TOP1:-none}";;
  esac
fi

# --- Summary ------------------------------------------------------------------
echo "----------------------------------------"
echo "$PASS passed, $FAIL failed, $INFO informational"
[ "$FAIL" -eq 0 ]
