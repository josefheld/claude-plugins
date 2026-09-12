#!/bin/sh
# Point Claude Code's statusLine at the copy of statusline-command.sh that
# ships with this plugin, so every plugin update also updates the script.
#
# Usage:
#   install-statusline.sh                        all segments, default order
#   install-statusline.sh model,context,git      only these, in this order
#   install-statusline.sh --project              write .claude/settings.json here
#   install-statusline.sh --show                 print what is configured now
#   install-statusline.sh --uninstall            remove the statusLine entry
set -eu

script=$(cd "$(dirname "$0")/.." && pwd)/statusline-command.sh
settings_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
segments=""
action="install"

for arg in "$@"; do
  case "$arg" in
    --project)   settings_dir="$PWD/.claude" ;;
    --show)      action="show" ;;
    --uninstall) action="uninstall" ;;
    --*)         echo "Unknown option: $arg" >&2; exit 2 ;;
    *)           segments="$arg" ;;
  esac
done
settings="$settings_dir/settings.json"

command -v jq >/dev/null 2>&1 || { echo "jq is required but not on PATH." >&2; exit 1; }
[ -f "$script" ] || { echo "Script not found: $script" >&2; exit 1; }

if [ "$action" = "show" ]; then
  if [ -f "$settings" ]; then
    jq '.statusLine // "not configured"' "$settings"
  else
    echo "\"$settings does not exist\""
  fi
  exit 0
fi

mkdir -p "$settings_dir"
[ -f "$settings" ] || echo '{}' > "$settings"

# Reject a settings.json that is not valid JSON instead of overwriting it.
jq -e . "$settings" >/dev/null 2>&1 || { echo "Not valid JSON, refusing to touch it: $settings" >&2; exit 1; }

# The pid keeps two runs in the same second from overwriting each other's backup.
backup="$settings.bak-$(date +%Y%m%d-%H%M%S)-$$"
cp "$settings" "$backup"

tmp="$settings.tmp-$$"
if [ "$action" = "uninstall" ]; then
  jq 'del(.statusLine)' "$settings" > "$tmp"
else
  if [ -n "$segments" ]; then
    cmd="CC_STATUSLINE_SEGMENTS=$segments sh $script"
  else
    cmd="sh $script"
  fi
  jq --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp"
fi
mv "$tmp" "$settings"

echo "Wrote $settings (backup: $backup)"
jq '.statusLine // "removed"' "$settings"
