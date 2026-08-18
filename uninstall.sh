#!/usr/bin/env bash
# ==============================================================================
# Omabot — Uninstaller Script for Omarchy
# ==============================================================================

set -e

PLUGIN_NAME="dorneles.omabot"
TARGET_DIR="${HOME}/.config/omarchy/plugins/${PLUGIN_NAME}"
BIN_LINK="${HOME}/.local/bin/omabot"
STATE_DIR="${HOME}/.local/state/omarchy/omabot"

echo "🗑️  Uninstalling Omabot..."

# Disable plugin if omarchy is available
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "${PLUGIN_NAME}" 2>/dev/null || true
fi

# Remove symlinks
if [ -L "${TARGET_DIR}" ] || [ -d "${TARGET_DIR}" ]; then
  rm -rf "${TARGET_DIR}"
  echo "✓ Removed ${TARGET_DIR}"
fi

if [ -L "${BIN_LINK}" ] || [ -f "${BIN_LINK}" ]; then
  rm -f "${BIN_LINK}"
  echo "✓ Removed ${BIN_LINK}"
fi

echo "✨ Omabot uninstalled successfully."
