#!/bin/sh
# End-to-end check for the `delegate` skill's one remaining backend path.
#
#   scripts/delegate-e2e.sh            # run it (spends one real delegated task)
#   scripts/delegate-e2e.sh --preflight # checks only, no backend call, no cost
#
# MANUAL ONLY. This is deliberately not reachable from scripts/validate.mjs:
# it needs a working AGENT_CMD and that backend's credentials, and CI has
# neither. Wiring it into the CI entry point would break every PR.
#
# What it proves: that the path the skill now depends on is actually
# executable — AGENT_CMD resolves, runs unattended, and completes a job that
# clears the skill's own bar (>5 files) against a machine-checked criterion.
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
cmd=$(printenv AGENT_CMD || true)
[ -n "$cmd" ] || fail "AGENT_CMD is unset. The skill requires one — see skills/delegate/references/setup.md.
       If you set it in a shell profile, this must run from a shell that sourced it."

command -v "$cmd" >/dev/null 2>&1 \
  || fail "AGENT_CMD is '$cmd' but that is not an executable on PATH.
       An alias will not work here — the skill invokes it non-interactively."

echo "ok: AGENT_CMD=$cmd -> $(command -v "$cmd")"

if [ "${1:-}" = "--preflight" ]; then
  echo "preflight only — no backend call made, nothing spent."
  exit 0
fi

# --- Fixture -----------------------------------------------------------------
work=$(mktemp -d "${TMPDIR:-/tmp}/delegate-e2e.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
trap 'rm -rf "$work"; exit 130' INT
trap 'rm -rf "$work"; exit 143' TERM

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
echo "running $cmd (a real delegated task; this may take a few minutes on a free backend)..."

# --- The delegated job -------------------------------------------------------
# Written the way SKILL.md says to write one: absolute paths, explicit scope,
# a machine-checkable criterion, and a bounded return contract.
prompt="In the directory $work, rename every occurrence of the function call
\`fetchUser\` to \`getUser\`. It appears once in each of the $FILE_COUNT .js
files there. Change nothing else — do not touch filenames, comments, or the
numeric arguments. Done = no occurrence of \`fetchUser\` remains in any .js
file under $work. Reply with at most 3 lines: the number of files you changed,
then PASS or FAIL for that criterion."

set +e
"$cmd" -p "$prompt" --allowedTools Read Glob Grep Edit
rc=$?
set -e

# --- Verification ------------------------------------------------------------
# Independent of whatever the backend reported about itself. A zero exit is not
# an acceptance signal: an agentic CLI exits 0 whenever the model completes a
# turn, including a turn that did nothing.
[ "$rc" -eq 0 ] || echo "note: backend exited $rc — verifying the files anyway" >&2

remaining=$(grep -l "fetchUser" "$work"/*.js 2>/dev/null | wc -l | tr -d ' ')
renamed=$(grep -l "getUser" "$work"/*.js 2>/dev/null | wc -l | tr -d ' ')

[ "$remaining" -eq 0 ] || fail "$remaining of $FILE_COUNT files still contain fetchUser"
[ "$renamed" -eq "$FILE_COUNT" ] || fail "expected $FILE_COUNT files renamed, found $renamed"

echo "PASS: $cmd completed a $FILE_COUNT-file job unattended and the criterion holds."
