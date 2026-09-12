#!/bin/sh
# Claude Code Status Line
# Single jq call, POSIX sh, one-line output.
#
# Configuration happens through environment variables in the settings.json
# entry, so there is no config file to parse on every render:
#
#   CC_STATUSLINE_SEGMENTS   comma-separated list, also defines the order
#   CC_STATUSLINE_BAR_WIDTH  characters per bar (default 8)
#   CC_STATUSLINE_WARN       yellow threshold in percent (default 70)
#   CC_STATUSLINE_CRIT       red threshold in percent (default 90)
#
# Segment names: model context cost limits dir git worktree duration
#                agent session style version codex

# printf and awk parse "62.4" through LC_NUMERIC. In a locale that uses a
# decimal comma (de_AT, fr_FR, ...) that is "invalid number" and the context
# and cost segments vanish. Only the numeric category is forced, so LC_CTYPE
# stays UTF-8 and the bar characters still render.
export LC_NUMERIC=C

: "${CC_STATUSLINE_SEGMENTS:=model,context,cost,limits,dir,git,worktree,duration,agent,session,style,version,codex}"
: "${CC_STATUSLINE_BAR_WIDTH:=8}"
# 24h by default: %p is an empty string in most non-English locales, which turns
# "2:30PM" into a bare "2:30". Set CC_STATUSLINE_TIME_FMT='%-I:%M%p' for 12h.
: "${CC_STATUSLINE_TIME_FMT:=%H:%M}"
: "${CC_STATUSLINE_WARN:=70}"
: "${CC_STATUSLINE_CRIT:=90}"

input=$(cat)

# --- Single jq parse for all fields ---
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "?")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "remaining=\(.context_window.remaining_percentage // "")",
  @sh "total_cost=\(.cost.total_cost_usd // "")",
  @sh "current_dir=\(.workspace.current_dir // "")",
  @sh "session_id=\(.session_id // "")",
  @sh "session_name=\(.session_name // "")",
  @sh "agent_name=\(.agent.name // "")",
  @sh "effort=\(.effort_level // "")",
  @sh "output_style=\(.output_style.name // "")",
  @sh "worktree=\(.worktree.name // "")",
  @sh "rl_5h_pct=\(.rate_limits.five_hour.used_percentage | if . == null then "" else (tostring | split(".")[0]) end)",
  @sh "rl_5h_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "rl_7d_pct=\(.rate_limits.seven_day.used_percentage | if . == null then "" else (tostring | split(".")[0]) end)",
  @sh "rl_7d_reset=\(.rate_limits.seven_day.resets_at // "")"
')"

# --- Colors ---
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MAGENTA='\033[35m'
DIM='\033[38;5;245m'
RST='\033[0m'

# --- Helpers ---
make_bar() {
  pct="$1"; width="$CC_STATUSLINE_BAR_WIDTH"
  filled=$(( pct * width / 100 ))
  i=0; bar=""
  while [ $i -lt $filled ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt $width ];  do bar="${bar}░"; i=$(( i + 1 )); done
  printf "%s" "$bar"
}

threshold_color() {
  pct="$1"
  if [ "$pct" -ge "$CC_STATUSLINE_CRIT" ] 2>/dev/null; then printf "%s" "$RED"
  elif [ "$pct" -ge "$CC_STATUSLINE_WARN" ] 2>/dev/null; then printf "%s" "$YELLOW"
  else printf "%s" "$GREEN"
  fi
}

parts=""
sep=" ${DIM}|${RST} "
add_part() { [ -n "$parts" ] && parts="${parts}${sep}"; parts="${parts}$1"; }

# --- Segments ---
# Every seg_* function appends at most one part and reads nothing but the
# parsed fields, so a segment that is turned off costs no work at all.

seg_model() {
  # Thinking mode: settings.json is only read when this segment is enabled.
  thinking=""
  if [ -f "$HOME/.claude/settings.json" ]; then
    [ "$(jq -r '.alwaysThinkingEnabled // empty' "$HOME/.claude/settings.json" 2>/dev/null)" = "true" ] && thinking="T"
  fi
  [ -z "$thinking" ] && [ -n "$MAX_THINKING_TOKENS" ] && thinking="T"
  [ -z "$effort" ] && [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ] && effort="$CLAUDE_CODE_EFFORT_LEVEL"

  s="$model"
  [ -n "$thinking" ] && s="${s} ${MAGENTA}${thinking}${RST}"
  [ -n "$effort" ] && [ "$effort" != "default" ] && s="${s} ${DIM}${effort}${RST}"
  add_part "🤖 ${s}"
}

seg_context() {
  # Always shows context *remaining*; the color follows what is used up.
  if [ -n "$remaining" ]; then
    rem=$(printf '%.0f' "$remaining")
  elif [ -n "$used" ]; then
    rem=$(( 100 - $(printf '%.0f' "$used") ))
  else
    return
  fi
  add_part "🧠 $(threshold_color $((100 - rem)))$(make_bar "$rem") ${rem}%${RST}"
}

seg_cost() {
  [ -n "$total_cost" ] || return
  add_part "💰 \$$(awk "BEGIN { printf \"%.2f\", $total_cost }")"
}

format_rl() {
  pct="$1"; reset_ts="$2"; label="$3"
  [ -n "$pct" ] || return
  reset_time=""
  if [ -n "$reset_ts" ]; then
    reset_time=$(date -r "$reset_ts" "+$CC_STATUSLINE_TIME_FMT" 2>/dev/null || date -d "@$reset_ts" "+$CC_STATUSLINE_TIME_FMT" 2>/dev/null)
    [ -n "$reset_time" ] && reset_time=" ↻${reset_time}"
  fi
  printf "%s%s %s %s%%%s%s" "$(threshold_color "$pct")" "$label" "$(make_bar "$pct")" "$pct" "$reset_time" "$RST"
}

seg_limits() {
  rl_str=$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h")
  rl_7d=$(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d")
  if [ -n "$rl_7d" ]; then
    [ -n "$rl_str" ] && rl_str="${rl_str} ${DIM}·${RST} ${rl_7d}" || rl_str="$rl_7d"
  fi
  [ -n "$rl_str" ] || return
  add_part "⏱️  ${rl_str}"
}

seg_dir() {
  [ -n "$current_dir" ] || return
  repo_root=$(cd "$current_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
  add_part "📁 ${CYAN}$(basename "$repo_root")${RST}"
}

seg_git() {
  [ -n "$current_dir" ] || return
  git_str=$(cd "$current_dir" 2>/dev/null || exit 1
    git rev-parse --git-dir >/dev/null 2>&1 || exit 1
    branch=$(git branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    out="$branch"
    [ "$staged" -gt 0 ] && out="${out} ${GREEN}+${staged}${RST}"
    [ "$modified" -gt 0 ] && out="${out} ${YELLOW}~${modified}${RST}"
    printf '%s' "$out")
  [ -n "$git_str" ] || return
  add_part "🌿 ${git_str}"
}

seg_worktree() {
  [ -n "$worktree" ] || return
  add_part "🌳 ${worktree}"
}

seg_duration() {
  [ -n "$session_id" ] || return
  session_dir="${TMPDIR:-/tmp}/claude-session-times"
  mkdir -p "$session_dir" 2>/dev/null || return
  session_file="$session_dir/$session_id"
  [ -f "$session_file" ] || date +%s > "$session_file"
  elapsed=$(( $(date +%s) - $(cat "$session_file") ))
  add_part "🕐 ${DIM}$(printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)))${RST}"
}

seg_agent() {
  [ -n "$agent_name" ] || return
  add_part "${MAGENTA}⚡${agent_name}${RST}"
}

seg_session() {
  [ -n "$session_name" ] || return
  add_part "${DIM}[${session_name}]${RST}"
}

seg_style() {
  [ -n "$output_style" ] && [ "$output_style" != "default" ] || return
  add_part "${DIM}${output_style}${RST}"
}

# version and codex each spawn a process on every render. Drop them from
# CC_STATUSLINE_SEGMENTS to save two subprocesses per redraw.
seg_version() {
  v=$(claude --version 2>/dev/null | head -1)
  [ -n "$v" ] || return
  add_part "${DIM}Claude ${v}${RST}"
}

seg_codex() {
  v=$(codex --version 2>/dev/null | head -1)
  [ -n "$v" ] || return
  add_part "${DIM}${v}${RST}"
}

# --- Assemble in the configured order ---
IFS=', '
for name in $CC_STATUSLINE_SEGMENTS; do
  case "$name" in
    model)    seg_model ;;
    context)  seg_context ;;
    cost)     seg_cost ;;
    limits)   seg_limits ;;
    dir)      seg_dir ;;
    git)      seg_git ;;
    worktree) seg_worktree ;;
    duration) seg_duration ;;
    agent)    seg_agent ;;
    session)  seg_session ;;
    style)    seg_style ;;
    version)  seg_version ;;
    codex)    seg_codex ;;
    *)        ;;   # unknown name: ignored, never breaks the status line
  esac
done
unset IFS

printf '%b' "$parts"
