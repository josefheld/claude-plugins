#!/bin/sh
# Self-check for statusline-command.sh: feeds a fixed JSON payload and asserts
# what the segment configuration does. Run it after editing the script.
#   sh plugins/statusline/test-statusline.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
script="$here/statusline-command.sh"

TMPDIR=$(mktemp -d)
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

fixture='{
  "model": {"display_name": "Opus 5"},
  "context_window": {"remaining_percentage": 62.4},
  "cost": {"total_cost_usd": 0.4242},
  "workspace": {"current_dir": "/tmp"},
  "session_id": "test-session",
  "session_name": "demo",
  "agent": {"name": "worker"},
  "output_style": {"name": "explanatory"},
  "worktree": {"name": "wt-1"},
  "rate_limits": {
    "five_hour": {"used_percentage": 45.9, "resets_at": 1757700000},
    "seven_day": {"used_percentage": 91.2, "resets_at": 1758000000}
  }
}'

esc=$(printf '\033')
run() { printf '%s' "$fixture" | env "$@" sh "$script" | sed "s/${esc}\[[0-9;]*m//g"; }

fails=0
check() { # check <description> <haystack> <needle> [absent]
  if [ "${4:-present}" = "absent" ]; then
    case "$2" in *"$3"*) echo "FAIL: $1 (found '$3')"; fails=$((fails+1)) ;; *) echo "ok: $1" ;; esac
  else
    case "$2" in *"$3"*) echo "ok: $1" ;; *) echo "FAIL: $1 (missing '$3')"; fails=$((fails+1)) ;; esac
  fi
}

# --- Defaults: every segment with data shows up ---
out=$(run CC_STATUSLINE_SEGMENTS=model,context,cost,limits,dir,git,worktree,duration,agent,session,style)
check "model name"        "$out" "🤖 Opus 5"
check "context remaining" "$out" "62%"
check "cost rounded"      "$out" '$0.42'
check "5h limit"          "$out" "5h"
check "7d limit"          "$out" "7d"
check "directory"         "$out" "📁"
check "worktree"          "$out" "🌳 wt-1"
check "duration"          "$out" "🕐 00:00:0"
check "agent"             "$out" "⚡worker"
check "session name"      "$out" "[demo]"
check "output style"      "$out" "explanatory"

# --- Segment selection turns the rest off ---
out=$(run CC_STATUSLINE_SEGMENTS=model,cost)
check "selection keeps model" "$out" "🤖 Opus 5"
check "selection keeps cost"  "$out" '$0.42'
check "selection drops bar"   "$out" "🧠" absent
check "selection drops dir"   "$out" "📁" absent
check "selection drops agent" "$out" "⚡" absent

# --- Order follows the list ---
out=$(run CC_STATUSLINE_SEGMENTS=cost,model)
case "$out" in
  '💰'*) echo "ok: order follows the list" ;;
  *)     echo "FAIL: order follows the list (got: $out)"; fails=$((fails+1)) ;;
esac

# --- Bar width is configurable ---
out=$(run CC_STATUSLINE_SEGMENTS=context CC_STATUSLINE_BAR_WIDTH=4)
width=$(printf '%s' "$out" | grep -o '[█░]' | wc -l | tr -d ' ')
[ "$width" = "4" ] && echo "ok: bar width 4" || { echo "FAIL: bar width 4 (got $width)"; fails=$((fails+1)); }

# --- Thresholds are configurable: 62% remaining = 38% used ---
red=$(printf '%s' "$(printf '%s' "$fixture" | env CC_STATUSLINE_SEGMENTS=context CC_STATUSLINE_CRIT=30 sh "$script")")
check "crit threshold colors red" "$red" "${esc}[31m"

# --- Unknown names are ignored, not fatal ---
out=$(run CC_STATUSLINE_SEGMENTS=model,bogus,cost)
check "unknown segment ignored" "$out" "🤖 Opus 5"
check "unknown segment keeps rest" "$out" '$0.42'

# --- Reset time format is configurable and never empty ---
out=$(run CC_STATUSLINE_SEGMENTS=limits)
check "24h reset time" "$out" "↻"
case "$out" in *"↻ "*|*"↻%"*) echo "FAIL: reset time not empty"; fails=$((fails+1)) ;; *) echo "ok: reset time not empty" ;; esac

# --- Missing rate limits must not print "null%" ---
out=$(printf '%s' '{"model":{"display_name":"Opus 5"}}' | env CC_STATUSLINE_SEGMENTS=model,limits sh "$script" | sed "s/${esc}\[[0-9;]*m//g")
check "no null rate limit" "$out" "null" absent
check "no empty limit bar" "$out" "⏱" absent

# --- Empty payload must not error out ---
if printf '{}' | sh "$script" >/dev/null 2>&1; then
  echo "ok: empty payload survives"
else
  echo "FAIL: empty payload survives"; fails=$((fails+1))
fi

echo
[ "$fails" = "0" ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }
