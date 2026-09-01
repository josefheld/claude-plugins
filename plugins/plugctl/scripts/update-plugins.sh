#!/usr/bin/env bash
# Aktualisiert alle Marketplaces und danach jedes installierte Plugin einzeln.
#
# Hintergrund: "claude plugin update" verlangt zwingend ein Plugin-Argument,
# ein --all gibt es (Stand 09/2026) nicht. Diese Schleife ist der Ersatz.
# "claude plugin marketplace update" allein reicht nicht: das frischt nur den
# Katalog auf, die installierte Version im Plugin-Cache bleibt unveraendert.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$HERE/list-plugin-ids.js"

DRY_RUN=0
SCOPE=""
ONLY=""
SKIP_MARKETPLACE=0

usage() {
  cat <<'EOF'
update-plugins.sh [OPTIONS]

  --dry-run           Only show what would be updated
  --check             Alias for --dry-run
  --scope <scope>     Passed through to "claude plugin update" (user|project|local|managed)
  --only <name>       Update this one plugin only
  --no-marketplace    Skip the marketplace refresh
  -h, --help          This help

Exit codes: 0 = all good, 1 = some plugins failed, 2 = aborted
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|--check) DRY_RUN=1; shift ;;
    --scope) SCOPE="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --no-marketplace) SKIP_MARKETPLACE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for bin in claude node; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing from PATH: $bin" >&2; exit 2; }
done
[ -f "$PARSER" ] || { echo "Parser not found: $PARSER" >&2; exit 2; }

# --- 1. Refresh marketplaces ---------------------------------------------
# Without this, Claude Code never learns about new versions in the catalog and
# every plugin update wrongly reports "already at the latest version".
if [ "$SKIP_MARKETPLACE" -eq 0 ]; then
  echo "==> Refreshing marketplaces"
  if ! claude plugin marketplace update </dev/null; then
    echo "    Warning: marketplace refresh failed, continuing anyway" >&2
  fi
  echo
fi

# --- 2. Determine installed plugins ---------------------------------------
raw="$(claude plugin list --json </dev/null 2>/dev/null)" || {
  echo "\"claude plugin list --json\" failed" >&2; exit 2; }

ids="$(printf '%s' "$raw" | node "$PARSER")"
parser_rc=$?

if [ $parser_rc -ne 0 ] || [ -z "$ids" ]; then
  echo "Keine Plugins erkannt. Rohe Ausgabe zum Nachsehen:" >&2
  printf '%s\n' "$raw" | head -c 800 >&2
  echo >&2
  exit 2
fi

# --- 3. Jedes Plugin einzeln aktualisieren --------------------------------
updated=0; current=0; failed=0; skipped=0
failed_names=""

while IFS= read -r id; do
  [ -n "$id" ] || continue

  if [ -n "$ONLY" ] && [ "$id" != "$ONLY" ] && [ "${id%%@*}" != "$ONLY" ]; then
    continue
  fi

  # "claude plugin update" does not know these sources: @skills-dir is local,
  # @synced comes from claude.ai, @inline from --plugin-dir.
  case "$id" in
    *@skills-dir|*@synced|*@inline)
      echo "--  $id (skipped, not a marketplace plugin)"
      skipped=$((skipped + 1)); continue ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "--  $id (dry-run)"
    continue
  fi

  # "claude plugin update" nimmt ohne --scope immer "user". Plugins, die im
  # project-, local- oder managed-Scope installiert sind, scheitern dann mit
  # "is not installed at scope user". Darum der Reihe nach durchprobieren,
  # sofern der Aufrufer nicht selbst einen Scope vorgegeben hat.
  if [ -n "$SCOPE" ]; then
    scopes="$SCOPE"
  else
    scopes="user project local managed"
  fi

  out=""; rc=1; used_scope=""
  for sc in $scopes; do
    # </dev/null verhindert Haenger an der Bestaetigung, die Plugins mit
    # "command source" beim Update stellen.
    out="$(claude plugin update "$id" --scope "$sc" </dev/null 2>&1)"
    rc=$?
    used_scope="$sc"
    [ $rc -eq 0 ] && break
    # Only keep searching on a scope mismatch, report real errors immediately.
    printf '%s' "$out" | grep -qiE 'not installed at scope' || break
  done

  scope_note=""
  [ $rc -eq 0 ] && [ "$used_scope" != "user" ] && scope_note=" [scope: $used_scope]"

  if [ $rc -ne 0 ]; then
    echo "!!  $id"
    printf '%s\n' "$out" | sed 's/^/      /'
    failed=$((failed + 1))
    failed_names="$failed_names $id"
  elif printf '%s' "$out" | grep -qiE 'already|latest|up to date|no update'; then
    echo "==  $id$scope_note"
    current=$((current + 1))
  else
    echo "OK  $id$scope_note"
    printf '%s\n' "$out" | sed 's/^/      /'
    updated=$((updated + 1))
  fi
done <<EOF
$ids
EOF

# --- 4. Zusammenfassung ---------------------------------------------------
echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry-run beendet, nichts veraendert."
  exit 0
fi

echo "$updated updated, $current already current, $failed failed, $skipped skipped."
[ -n "$failed_names" ] && echo "Fehlgeschlagen:$failed_names"

if [ "$updated" -gt 0 ]; then
  echo
  echo "Hinweis: in einer laufenden Session /reload-plugins ausfuehren,"
  echo "sonst greifen die neuen Versionen erst beim naechsten Start."
fi

[ "$failed" -gt 0 ] && exit 1
exit 0
