#!/usr/bin/env bash
# ==============================================================================
# Omabot — Installer Script for Omarchy
# AI Bot & Prompt Directory (https://github.com/jvlianodorneles/omabot)
# Data source: https://github.com/elie222/botdirectory.ai
# ==============================================================================

set -e

PLUGIN_NAME="dorneles.omabot"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.config/omarchy/plugins/${PLUGIN_NAME}"
STATE_DIR="${HOME}/.local/state/omarchy/omabot"
BIN_DIR="${HOME}/.local/bin"
MENU_FILE="${HOME}/.config/omarchy/extensions/omarchy-menu.jsonc"

echo "🤖 Installing Omabot (AI Bot & Prompt Directory for Omarchy)..."

# Ensure directories
mkdir -p "${HOME}/.config/omarchy/plugins"
mkdir -p "${STATE_DIR}"
mkdir -p "${BIN_DIR}"

# Initialize local state cache from builtin data
if [ ! -f "${STATE_DIR}/bots.json" ] && [ -f "${SOURCE_DIR}/data/bots.json" ]; then
  cp "${SOURCE_DIR}/data/bots.json" "${STATE_DIR}/bots.json"
  echo "✓ Initialized bot directory cache at ${STATE_DIR}/bots.json"
fi

# Symlink plugin directory
if [ -L "${TARGET_DIR}" ] || [ -d "${TARGET_DIR}" ]; then
  rm -rf "${TARGET_DIR}"
fi

ln -sfn "${SOURCE_DIR}" "${TARGET_DIR}"
echo "✓ Symlinked plugin to ${TARGET_DIR}"

# Ensure scripts are executable
chmod +x "${SOURCE_DIR}/scripts/"*

# Symlink CLI tool to ~/.local/bin/omabot
ln -sfn "${SOURCE_DIR}/scripts/omabot-sync.py" "${BIN_DIR}/omabot"
echo "✓ Linked 'omabot' CLI command to ${BIN_DIR}/omabot"

# Validate plugin with omarchy CLI
if command -v omarchy >/dev/null 2>&1; then
  echo "Validating plugin manifest with Omarchy..."
  omarchy plugin validate "${SOURCE_DIR}"
  echo "✓ Plugin manifest validated successfully!"
fi

# Optional menu registration
if [ -f "${MENU_FILE}" ]; then
  python3 -c "
import json
menu_path = '${MENU_FILE}'
try:
    with open(menu_path, 'r') as f:
        content = f.read()
    if 'dorneles.omabot' not in content:
        entry = '''  \"tools.ai.omabot\": {\"icon\":\"󰚩\",\"label\":\"Omabot (AI Bot Directory)\",\"action\":\"omarchy-shell dorneles.omabot toggle\",\"aliases\":[\"omabot\",\"bot directory\",\"prompts\",\"ai bot\"]},\n'''
        pos = content.rfind('}')
        if pos != -1:
            new_content = content[:pos] + entry + content[pos:]
            with open(menu_path, 'w') as f:
                f.write(new_content)
            print('✓ Registered Omabot in Omarchy Application Menu')
except Exception as e:
    pass
"
fi

echo ""
echo "✨ Omabot installed successfully!"
echo ""
echo "🚀 Quick Start:"
echo "  • Enable bar widget:  omarchy plugin enable dorneles.omabot"
echo "  • Toggle popup:       omarchy-shell dorneles.omabot toggle"
echo "  • Search CLI:         omabot search \"code review\""
echo "  • Sync latest bots:   omabot sync"
echo ""
