#!/bin/bash
# Per-machine settings the `orchestrator` plugin cannot ship: which model runs the
# main thread, which runs subagents, and the DELEGATE_CHILD marker in each backend
# launcher so the gate hook lets delegated runs through.
#
#   scripts/orchestrator-settings.sh              # main=fable, subagents=opus
#   scripts/orchestrator-settings.sh opus sonnet  # any two model aliases
#
# Idempotent. Backs up ~/.claude/settings.json to settings.json.bak first.
set -e
MAIN="${1:-fable}"
SUB="${2:-opus}"
SETTINGS="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq / apt install jq)"; exit 1; }

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"
jq --arg main "$MAIN" --arg sub "$SUB" \
   '.model = $main | .env = ((.env // {}) + {"CLAUDE_CODE_SUBAGENT_MODEL": $sub})' \
   "$SETTINGS.bak" > "$SETTINGS"
echo "settings: model=$MAIN, subagents=$SUB (backup at $SETTINGS.bak)"

IFS=';' read -ra backends <<< "${DELEGATE_BACKENDS:-}"
if [ "${#backends[@]}" -eq 0 ]; then
  echo "DELEGATE_BACKENDS is unset in this shell — set up the delegate backends first (README), then re-run."
  exit 0
fi
for b in "${backends[@]}"; do
  b="${b## }"; b="${b%% }"; [ -n "$b" ] || continue
  f="$(command -v "$b" 2>/dev/null || true)"
  if [ -z "$f" ]; then echo "launcher $b: not on PATH, skipped"; continue; fi
  if grep -q 'DELEGATE_CHILD' "$f"; then echo "launcher $b: already marked"; continue; fi
  if grep -q '^exec claude ' "$f"; then
    perl -pi -e 's/^exec claude /export DELEGATE_CHILD=1\nexec claude /' "$f"
    echo "launcher $b: added export DELEGATE_CHILD=1"
  else
    echo "launcher $b: add 'export DELEGATE_CHILD=1' before its exec line by hand ($f)"
  fi
done
