# 🤖 Omabot — AI Bot & Prompt Directory for Omarchy

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Omarchy%20%7C%20Quickshell-ff79c6.svg)](https://github.com/jvlianodorneles/omabot)
[![Data Source](https://img.shields.io/badge/Data%20Source-botdirectory.ai-blueviolet.svg)](https://github.com/elie222/botdirectory.ai)

**Omabot** is a native, modern, flat-design status bar plugin and popup directory for [Omarchy](https://github.com/jvlianodorneles/omabot) that lets you search, explore, and 1-click copy AI bot system prompts from [botdirectory.ai](https://github.com/elie222/botdirectory.ai).

---

## ✨ Features

* **🤖 Status Bar Integration**: Displays a clean robot icon (`󰚩`) on the main bar with active states, popout coordination, and tooltips.
* **🔍 Instant Search**: Real-time keyword filtering across bot names, system prompt contents, categories, and contributor tags.
* **🏷️ Category Filtering**: Filter bots across categories including `All`, `Coding`, `Writing`, `Marketing`, `Sales`, `Ops`, `Design`, `Productivity`, `Success`, and `Personal`.
* **📋 1-Click Clipboard Copy**: One-click copying to system clipboard (Wayland `wl-copy` / X11) with instant visual feedback (icon changes to checkmark `󰄬`).
* **🎨 Native System Theme**: Follows system colors, typography, border radii, and dark/light modes out of the box.
* **⚡ Offline-Ready + Live Sync**: Pre-bundled with 140+ popular AI agent and bot prompts; syncs live from GitHub API and [botdirectory.ai](https://github.com/elie222/botdirectory.ai).
* **💻 CLI & Keyboard First**: Includes `omabot` CLI and full IPC support for Hyprland keybindings.

---

## 📐 Layout & Design

The popup window follows a clean 3-tier vertical structure:

```
┌─────────────────────────────────────────────────────────┐
│ [󰍉 Search bots...                                  ✕] │  ← Header: Centered Search Input
│                                  CATEGORIES: [ All 󰅀 ] │  ← Header: Category Dropdown
├─────────────────────────────────────────────────────────┤
│ ChatGPT Prompter                              [ 󰆏 ]     │
│ Um assistente especializado em criar prompts...        │
├─────────────────────────────────────────────────────────┤
│ Midjourney Architect                          [ 󰆏 ]     │
│ Gera descrições hiper-realistas para projetos...        │
├─────────────────────────────────────────────────────────┤
│ CodeReview Bot                                [ 󰆏 ]     │
│ Analisa pequenos snippets de código buscando...        │
├─────────────────────────────────────────────────────────┤
│                     omabot — data source 󰌹             │  ← Footer: Clickable Reference
└─────────────────────────────────────────────────────────┘
```

1. **Header (Control Area)**:
   * **Search Bar**: Centered input box with an internal dark-grey magnifying glass (`󰍉`), clear button (`✕`), and instant query debouncing.
   * **Category Filter**: Positioned directly below the search bar on the right, featuring the `"CATEGORIES"` uppercase label and a selector dropdown with a chevron icon (`󰅀`).
2. **Results List (Central Area)**:
   * Vertical scrollable list with a sleek, minimalist scroll indicator.
   * Fine divider lines between bot cards.
   * **Bot Name**: Slightly bold title.
   * **Prompt Preview**: 2-line wrapped excerpt.
   * **Copy Button**: Aligned to the right with two overlapping documents icon (`󰆏`) that flips to a green checkmark (`󰄬`) on copy.
3. **Footer**:
   * Anchored bottom bar with `"omabot — data source"` linking directly to [elie222/botdirectory.ai](https://github.com/elie222/botdirectory.ai).

---

## 🚀 Installation

### 1. Clone or Download

```bash
git clone https://github.com/jvlianodorneles/omabot.git ~/omabot
cd ~/omabot
```

### 2. Run Installer

```bash
./install.sh
```

### 3. Enable in Omarchy

```bash
omarchy plugin enable dorneles.omabot
```

---

## ⌨️ Hyprland Keybinding (Optional)

Add a shortcut to `~/.config/hypr/hyprland.conf`:

```ini
# Toggle Omabot AI Directory (Super + B)
bind = $mainMod, B, exec, omarchy-shell dorneles.omabot toggle
```

---

## 🖥️ Command Line Interface (CLI)

The installed `omabot` command lets you browse and copy prompts directly from your terminal:

```bash
# List all bots
omabot list

# Filter by category
omabot list --category Coding

# Search bots
omabot search "code review"

# Copy a prompt directly to clipboard
omabot copy codereview-bot

# Sync latest prompts from botdirectory.ai
omabot sync

# Open data source repository in browser
omabot open
```

---

## 🛠️ IPC Commands

Control Omabot dynamically via `omarchy-shell`:

```bash
# Open popup
omarchy-shell dorneles.omabot open

# Toggle popup
omarchy-shell dorneles.omabot toggle

# Trigger data synchronization
omarchy-shell dorneles.omabot refresh

# Open directly with search filter
omarchy-shell dorneles.omabot search "architect"

# Copy prompt by slug
omarchy-shell dorneles.omabot copy "chatgpt-prompter"
```

---

## 📦 File Structure

```
omabot/
├── manifest.json            # Omarchy plugin manifest & configuration schema
├── BarWidget.qml            # Top bar widget with robot icon & popout coordinator
├── Panel.qml                # Popup window (3-tier layout: Search, List, Footer)
├── Model.js                 # Data filtering, category extraction & search logic
├── data/
│   └── bots.json            # Pre-bundled offline dataset (140+ AI bots)
├── scripts/
│   └── omabot-sync.py       # Sync engine & CLI tool (`omabot`)
├── install.sh               # One-step installation script
├── uninstall.sh             # Clean uninstallation script
├── LICENSE                  # MIT License
└── README.md                # Documentation & usage guide
```

---

## 🌐 Data Source & Attribution

All bot prompts and configurations are aggregated from the open-source [botdirectory.ai](https://github.com/elie222/botdirectory.ai) project by [Elie Steinbock](https://github.com/elie222) and the community.

---

## 📄 License

MIT © [Dorneles](https://github.com/jvlianodorneles)
