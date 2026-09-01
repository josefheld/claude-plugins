#!/usr/bin/env bash
#
# Setup script for fal-image-generator skill.
# Creates a Python virtualenv, installs dependencies, verifies the API key is
# set, and runs the offline self-test.
#
# The venv lives OUTSIDE the skill directory on purpose. A marketplace install
# unpacks the plugin into a versioned cache directory that is replaced on every
# update, so a venv kept next to the code would be deleted by each update. The
# cache path below survives that.
#
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SKILL_DIR/scripts"
VENV_DIR="${FAL_IMAGE_VENV:-${XDG_CACHE_HOME:-$HOME/.cache}/fal-image-generator/venv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# ---- colors ----
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; BOLD=""; RESET=""
fi

echo "${BOLD}fal-image-generator setup${RESET}"
echo "  skill dir: $SKILL_DIR"
echo "  venv:      $VENV_DIR"
echo ""

# ---- Python check ----
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "${RED}❌ Python3 not found. Install with: brew install python3${RESET}"
  exit 1
fi
PY_VERSION=$("$PYTHON_BIN" --version | awk '{print $2}')
echo "${GREEN}✓${RESET} Python: $PY_VERSION"

# ---- venv setup ----
if [[ -d "$VENV_DIR" ]]; then
  echo "${YELLOW}⚠${RESET}  venv already exists at $VENV_DIR"
  read -p "  Recreate? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf "$VENV_DIR"
  fi
fi

if [[ ! -d "$VENV_DIR" ]]; then
  echo "  Creating venv..."
  mkdir -p "$(dirname "$VENV_DIR")"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
  echo "${GREEN}✓${RESET} venv created"
fi

# ---- install deps ----
echo "  Installing dependencies..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r "$SCRIPTS_DIR/requirements.txt"
echo "${GREEN}✓${RESET} Dependencies installed"

# ---- API key check ----
# Deliberately do NOT print a prefix of the key: otherwise the value ends up
# in terminal scrollback, CI logs, and agent transcripts. Length is proof enough.
if [[ -z "${FAL_KEY:-}" ]]; then
  echo ""
  echo "${YELLOW}⚠${RESET}  FAL_KEY not set in current shell."
  echo "  Add this to your ~/.zshrc or ~/.bashrc:"
  echo ""
  echo "    export FAL_KEY=\"your-api-key-here\""
  echo ""
  echo "  Get a key at: https://fal.ai/dashboard/keys"
else
  echo "${GREEN}✓${RESET} FAL_KEY is set (${#FAL_KEY} chars)"
fi

# ---- generate.py executable ----
chmod +x "$SCRIPTS_DIR/generate.py"
echo "${GREEN}✓${RESET} generate.py is executable"

# ---- offline self-test (no API calls, no cost) ----
echo "  Running self-test..."
"$VENV_DIR/bin/python3" "$SCRIPTS_DIR/generate.py" --self-test

# ---- summary ----
echo ""
echo "${BOLD}Setup complete.${RESET}"
echo ""
echo "Test it (costs ~\$0.025):"
echo "  $VENV_DIR/bin/python3 $SCRIPTS_DIR/generate.py \\"
echo "    --prompt \"A minimalist tech illustration\" \\"
echo "    --output /tmp/test.webp \\"
echo "    --resolution 1K --aspect 16:9"
