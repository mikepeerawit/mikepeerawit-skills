#!/bin/sh
# End-to-end check for the `delegate` skill's one remaining backend path.
#
#   scripts/delegate-e2e.sh            # run it (spends one real delegated task)
#   scripts/delegate-e2e.sh --preflight # checks only, no backend call, no cost
#
# MANUAL ONLY. This is deliberately not reachable from scripts/validate.mjs:
# it needs a working DELEGATE_BACKENDS and those backends' credentials, and CI
# has neither. Wiring it into the CI entry point would break every PR.
#
# What it proves: that the path the skill now depends on is actually
# executable — every entry in DELEGATE_BACKENDS resolves, and the list as a
# whole runs unattended through to a job that clears the skill's own bar
# (>5 files) against a machine-checked criterion.
#
# What it does NOT prove: that the model *chooses* this path over doing the
# work inline. That is a live-session behaviour, and no shell script can
# observe it. Since ADR-0001 the wrong choice no longer exists as an option,
# so what's left to verify is that the surviving option works.

set -eu

FILE_COUNT=8   # must exceed the skill's >5 files bar

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Preconditions -----------------------------------------------------------
# `printenv`, not `echo`, because that is the check the skill itself prescribes.
backends=$(printenv DELEGATE_BACKENDS || true)
[ -n "$backends" ] || fail "DELEGATE_BACKENDS is unset. The skill requires at least one
       backend — see the Setup section of skills/delegate/SKILL.md. If you set it
       in a shell profile, this must run from a shell that sourced it."

# Every entry has to resolve, not just the first: the whole point of a list is
# the fallback, and a typo in entry 2 only surfaces the day entry 1 goes down.
old_ifs=$IFS
IFS=';'
for cmd in $backends; do
  IFS=$old_ifs
  [ -n "$cmd" ] || continue
  command -v "$cmd" >/dev/null 2>&1 \
    || fail "DELEGATE_BACKENDS lists '$cmd', which is not an executable on PATH.
       An alias will not work here — the skill invokes these non-interactively."
  echo "ok: backend '$cmd' -> $(command -v "$cmd")"
  IFS=';'
done
IFS=$old_ifs

if [ "${1:-}" = "--preflight" ]; then
  echo "preflight only — no backend call made, nothing spent."
  exit 0
fi

# --- Fixture -----------------------------------------------------------------
work=$(mktemp -d "${TMPDIR:-/tmp}/delegate-e2e.XXXXXX") || exit 1
run_out=$(mktemp "${TMPDIR:-/tmp}/delegate-e2e-out.XXXXXX") || exit 1
# INT/TERM must exit, not just clean up: a cleanup-only handler lets the script
# run on after Ctrl-C, reading the cancelled run as a dead backend and billing
# the paid one for work that was interrupted on purpose.
trap 'rm -rf "$work" "$run_out"' EXIT
trap 'rm -rf "$work" "$run_out"; exit 130' INT
trap 'rm -rf "$work" "$run_out"; exit 143' TERM

i=1
while [ "$i" -le "$FILE_COUNT" ]; do
  cat >"$work/mod$i.js" <<EOF
// module $i
export function callSite$i() {
  return fetchUser($i);
}
EOF
  i=$((i + 1))
done

echo "ok: fixture built — $FILE_COUNT files in $work"
echo "running the backend list (a real delegated task; minutes, on a free backend)..."

# --- The delegated job -------------------------------------------------------
# Written the way SKILL.md says to write one: absolute paths, explicit scope,
# a machine-checkable criterion, and a bounded return contract.
prompt="In the directory $work, rename every occurrence of the function call
\`fetchUser\` to \`getUser\`. It appears once in each of the $FILE_COUNT .js
files there. Change nothing else — do not touch filenames, comments, or the
numeric arguments. Done = no occurrence of \`fetchUser\` remains in any .js
file under $work. Reply with at most 3 lines: the number of files you changed,
then PASS or FAIL for that criterion."

# --- Run the list ------------------------------------------------------------
# Verification is independent of whatever a backend reported about itself. A
# zero exit is not an acceptance signal: an agentic CLI exits 0 whenever the
# model completes a turn, including a turn that did nothing.
#
# Falling through to the next backend needs BOTH of the skill's conditions, and
# getting either wrong costs real money on the paid backend:
#
#   1. The backend actually failed, rather than running and doing nothing. An
#      agentic CLI exits 0 whenever the model completes a turn — including a
#      turn that reported FAIL. That is task-level: the next backend gets the
#      same prompt and fails the same way, so the run ends instead.
#      Claude Code prints API/auth errors to STDOUT and exits 1, so the marker
#      is the nonzero exit, not an empty stream.
#   2. The fixture is untouched — the skill's "check git status first". Once a
#      backend has edited files, re-running would double-apply those edits.
untouched() { ! grep -lq "getUser" "$work"/*.js 2>/dev/null; }

backend_failed() {
  [ "$1" -eq 0 ] && return 1
  [ ! -s "$2" ] && return 0
  [ "$(wc -c <"$2")" -gt 2000 ] && return 1
  grep -qiE 'API Error|Failed to authenticate|Connection error|fetch failed|ECONNREFUSED|ETIMEDOUT|Internal server error|Bad gateway|Service Unavailable' "$2"
}

IFS=';'
for cmd in $backends; do
  IFS=$old_ifs
  [ -n "$cmd" ] || continue

  echo "--- $cmd"
  # --add-dir is not optional: the fixture lives outside the cwd, and without it
  # the backend reports the directory as nonexistent and does nothing.
  #
  # Buffered to a file rather than piped to tee, because `rc=$?` after a
  # pipeline is tee's status, not the backend's — which would defeat the
  # nonzero-exit test that decides whether to spend the paid backend.
  set +e
  "$cmd" -p "$prompt" --allowedTools Read Glob Grep Edit --add-dir "$work" >"$run_out" 2>&1
  rc=$?
  set -e
  cat "$run_out"

  remaining=$(grep -l "fetchUser" "$work"/*.js 2>/dev/null | wc -l | tr -d ' ')
  renamed=$(grep -l "getUser" "$work"/*.js 2>/dev/null | wc -l | tr -d ' ')

  if [ "$remaining" -eq 0 ] && [ "$renamed" -eq "$FILE_COUNT" ]; then
    echo "PASS: $cmd completed a $FILE_COUNT-file job unattended and the criterion holds."
    exit 0
  fi

  untouched \
    || fail "$cmd left the fixture half-done ($renamed/$FILE_COUNT renamed, exit $rc).
       That is a task-level failure — the skill does not fall through on those."

  backend_failed "$rc" "$run_out" \
    || fail "$cmd ran (exit $rc) but renamed $renamed/$FILE_COUNT files.
       That is a task-level failure, not a dead backend — the skill does not fall
       through on those, so neither does this. Fix the prompt, not the backend."

  echo "note: $cmd failed at backend level (exit $rc) — falling through." >&2
  IFS=';'
done
IFS=$old_ifs

fail "every backend in DELEGATE_BACKENDS failed to do the job."
