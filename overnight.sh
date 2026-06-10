#!/usr/bin/env bash
# overnight.sh — run from the repo root in Git Bash (MINGW64)
# Spins up fresh Claude Code sessions in a loop until END_HOUR or roadmap completion.
set -uo pipefail

BRANCH="overnight/world-update"
END_HOUR=7                       # stop at 7:00 AM local time
DEFAULT_MODEL="claude-fable-5"   # Session 1 (Phase 0 audit) always runs on this
DEFAULT_EFFORT="high"
PROMPT_FILE="OVERNIGHT_PROMPT.md"
MAX_TURNS=200                    # per-session ceiling; the prompt's own protocol ends sessions earlier
LOG_DIR=".overnight-logs"

# Reads the routing decision the agent wrote in its last handoff block.
# Falls back to defaults if missing or malformed, so a typo can't kill the run.
next_model() {
  local m
  m=$(grep -oE 'NEXT_MODEL: *claude-[a-z0-9.-]+' ROADMAP.md 2>/dev/null | tail -1 | awk '{print $2}')
  case "$m" in
    claude-fable-5|claude-opus-4-8|claude-sonnet-4-6) echo "$m" ;;
    *) echo "$DEFAULT_MODEL" ;;
  esac
}

next_effort() {
  local e
  e=$(grep -oE 'NEXT_EFFORT: *[a-z]+' ROADMAP.md 2>/dev/null | tail -1 | awk '{print $2}')
  case "$e" in
    low|medium|high|xhigh) echo "$e" ;;
    *) echo "$DEFAULT_EFFORT" ;;
  esac
}

mkdir -p "$LOG_DIR"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: $PROMPT_FILE not found in $(pwd). Put it in the repo root." >&2
  exit 1
fi

# Dedicated branch so main is never touched
git rev-parse --verify "$BRANCH" >/dev/null 2>&1 && git checkout "$BRANCH" || git checkout -b "$BRANCH"

# Compute the stop time (handles starting before or after midnight)
if [ "$((10#$(date +%H)))" -ge "$END_HOUR" ]; then
  end_epoch=$(date -d "tomorrow ${END_HOUR}:00" +%s)
else
  end_epoch=$(date -d "today ${END_HOUR}:00" +%s)
fi
echo "Running until $(date -d "@$end_epoch")" | tee -a "$LOG_DIR/run.log"

session=1
while [ "$(date +%s)" -lt "$end_epoch" ]; do
  MODEL=$(next_model)
  EFFORT=$(next_effort)
  echo "=== Session $session — $(date) — model=$MODEL effort=$EFFORT ===" | tee -a "$LOG_DIR/run.log"

  start_ts=$(date +%s)
  claude -p "$(cat "$PROMPT_FILE")" \
    --model "$MODEL" \
    --effort "$EFFORT" \
    --dangerously-skip-permissions \
    --max-turns "$MAX_TURNS" \
    > "$LOG_DIR/session-$session.log" 2>&1
  duration=$(( $(date +%s) - start_ts ))

  echo "--- Session $session exited after ${duration}s ($(date)) ---" | tee -a "$LOG_DIR/run.log"

  # Clean termination signal defined in the master prompt
  if grep -q "ROADMAP COMPLETE" "$LOG_DIR/session-$session.log"; then
    echo "Roadmap complete — stopping early." | tee -a "$LOG_DIR/run.log"
    break
  fi

  # A real session takes many minutes. A fast exit means a usage limit,
  # auth issue, or crash — back off 20 min instead of hammering retries.
  if [ "$duration" -lt 120 ]; then
    echo "Fast exit (<2 min) — likely usage limit or error. Backing off 20 min." | tee -a "$LOG_DIR/run.log"
    tail -n 5 "$LOG_DIR/session-$session.log" | tee -a "$LOG_DIR/run.log"
    session=$((session + 1))
    sleep 1200
    continue
  fi

  session=$((session + 1))
  sleep 30   # brief breather between sessions; also softens rate-limit pressure
done

echo "Overnight run finished after $session session(s) — $(date)" | tee -a "$LOG_DIR/run.log"
echo "Review: git log --oneline on $BRANCH, plus ROADMAP.md handoff blocks."
