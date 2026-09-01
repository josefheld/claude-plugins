#!/usr/bin/env bash
#
# Install all skills from this repo into ~/.claude/skills/
#
# After symlinking each skill, automatically runs per-skill setup.sh
# (if present) for skills that need additional setup like Python venvs.
#
# Usage:
#   ./install.sh             # symlink mode (default, recommended)
#   ./install.sh --copy      # copy files instead of symlinking
#   ./install.sh --dry-run   # preview what would happen
#   ./install.sh --force     # overwrite existing skills without asking
#   ./install.sh --setup-all # run setup.sh for ALL skills (incl. already-linked)
#   ./install.sh --no-setup  # skip all setup.sh execution
#

set -euo pipefail

# ---- config ----
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
MODE="symlink"
DRY_RUN=false
FORCE=false
SETUP_ALL=false
NO_SETUP=false

# ---- colors ----
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; DIM=""; RESET=""
fi

# ---- args ----
for arg in "$@"; do
  case "$arg" in
    --copy)      MODE="copy" ;;
    --dry-run)   DRY_RUN=true ;;
    --force)     FORCE=true ;;
    --setup-all) SETUP_ALL=true ;;
    --no-setup)  NO_SETUP=true ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "${RED}Unknown arg: $arg${RESET}"; exit 1 ;;
  esac
done

# ---- header ----
echo "${BOLD}claude-skills installer${RESET}"
echo "  repo:   $REPO_DIR"
echo "  target: $SKILLS_DIR"
echo "  mode:   $MODE$($DRY_RUN && echo ' (dry-run)' || echo '')"
echo ""

# ---- ensure target dir exists ----
if ! $DRY_RUN; then
  mkdir -p "$SKILLS_DIR"
fi

# ---- discover skills ----
# A skill = any direct subdirectory of skills/ that contains a SKILL.md
skills=()
while IFS= read -r -d '' skill_md; do
  skill_dir="$(dirname "$skill_md")"
  skill_name="$(basename "$skill_dir")"
  parent="$(dirname "$skill_dir")"
  if [[ "$parent" == "$SKILLS_SRC" ]]; then
    skills+=("$skill_name")
  fi
done < <(find "$SKILLS_SRC" -maxdepth 2 -name "SKILL.md" -print0 2>/dev/null)

if [[ ${#skills[@]} -eq 0 ]]; then
  echo "${YELLOW}No skills found (looking for skills/*/SKILL.md in $REPO_DIR)${RESET}"
  exit 0
fi

echo "${BOLD}Found ${#skills[@]} skill(s):${RESET}"
for s in "${skills[@]}"; do
  hint=""
  [[ -x "$SKILLS_SRC/$s/setup.sh" ]] && hint=" ${DIM}(has setup.sh)${RESET}"
  echo "  • $s$hint"
done
echo ""

# ---- install loop ----
installed=0; skipped=0; replaced=0
newly_linked=()   # track which skills are fresh installs for setup.sh trigger

for skill in "${skills[@]}"; do
  src="$SKILLS_SRC/$skill"
  dst="$SKILLS_DIR/$skill"

  if [[ -e "$dst" || -L "$dst" ]]; then
    # already exists — check if it's our symlink
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
      echo "${BLUE}=${RESET} $skill ${YELLOW}(already linked, skipping)${RESET}"
      ((skipped++)) || true
      continue
    fi

    if ! $FORCE; then
      printf "${YELLOW}?${RESET} $skill exists at $dst. Replace? [y/N] "
      read -r answer </dev/tty || answer="n"
      if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "${YELLOW}  skipped${RESET}"
        ((skipped++)) || true
        continue
      fi
    fi

    if ! $DRY_RUN; then
      rm -rf "$dst"
    fi
    ((replaced++)) || true
  fi

  if $DRY_RUN; then
    echo "${GREEN}+${RESET} would $MODE: $skill"
  else
    if [[ "$MODE" == "symlink" ]]; then
      ln -s "$src" "$dst"
    else
      cp -R "$src" "$dst"
    fi
    echo "${GREEN}+${RESET} $skill"
  fi
  newly_linked+=("$skill")
  ((installed++)) || true
done

echo ""
echo "${BOLD}Install summary:${RESET} installed=$installed replaced=$replaced skipped=$skipped"

# ---- per-skill setup.sh execution ----
if ! $NO_SETUP && ! $DRY_RUN; then
  # Determine which skills get setup.sh: newly_linked (default) or all (--setup-all)
  if $SETUP_ALL; then
    setup_targets=("${skills[@]}")
  else
    setup_targets=("${newly_linked[@]:-}")
  fi

  setup_count=0
  for skill in "${setup_targets[@]:-}"; do
    [[ -z "$skill" ]] && continue
    setup_script="$SKILLS_SRC/$skill/setup.sh"
    if [[ -x "$setup_script" ]]; then
      echo ""
      echo "${BOLD}↳ Running setup.sh for $skill${RESET}"
      echo "${DIM}─────────────────────────────────────${RESET}"
      if bash "$setup_script"; then
        ((setup_count++)) || true
      else
        echo "${RED}❌ setup.sh failed for $skill (exit $?). Continuing.${RESET}"
      fi
      echo "${DIM}─────────────────────────────────────${RESET}"
    fi
  done

  if [[ $setup_count -gt 0 ]]; then
    echo ""
    echo "${GREEN}✓${RESET} Ran setup for $setup_count skill(s)."
  fi

  # Show skills with setup.sh that were NOT run (only when not --setup-all)
  if ! $SETUP_ALL; then
    untouched_with_setup=()
    for skill in "${skills[@]}"; do
      setup_script="$SKILLS_SRC/$skill/setup.sh"
      already_linked=true
      for fresh in "${newly_linked[@]:-}"; do
        [[ "$fresh" == "$skill" ]] && already_linked=false && break
      done
      if [[ -x "$setup_script" ]] && $already_linked; then
        untouched_with_setup+=("$skill")
      fi
    done

    if [[ ${#untouched_with_setup[@]} -gt 0 ]]; then
      echo ""
      echo "${DIM}Skills with setup.sh that were skipped (already linked):${RESET}"
      for s in "${untouched_with_setup[@]}"; do
        echo "  ${DIM}• $s${RESET}"
      done
      echo "${DIM}Re-run setup with: ./install.sh --setup-all${RESET}"
    fi
  fi
fi

# ---- closing tip ----
if [[ "$MODE" == "symlink" && $installed -gt 0 ]] && ! $DRY_RUN; then
  echo ""
  echo "${BLUE}Tip:${RESET} since these are symlinks, ${BOLD}git pull${RESET} in this repo"
  echo "will update the skills automatically — no re-install needed."
fi
