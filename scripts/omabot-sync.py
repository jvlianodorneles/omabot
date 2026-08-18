#!/usr/bin/env python3
"""
omabot-sync.py - Sync engine, prompt manager, and CLI for Omabot (Omarchy AI Bot Directory).
"""

import os
import sys
import json
import argparse
import subprocess
import shutil
import tempfile

UPSTREAM_REPO = "https://github.com/elie222/botdirectory.ai.git"
SOURCE_REPO = "https://github.com/elie222/botdirectory.ai"
STATE_DIR = os.path.expanduser("~/.local/state/omarchy/omabot")
CACHE_FILE = os.path.join(STATE_DIR, "bots.json")
FAVORITES_FILE = os.path.join(STATE_DIR, "favorites.json")
RECENTS_FILE = os.path.join(STATE_DIR, "recents.json")
CUSTOM_BOTS_FILE = os.path.join(STATE_DIR, "custom_bots.json")
SHELL_CONFIG_FILE = os.path.expanduser("~/.config/omarchy/shell.json")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGIN_ROOT = os.path.dirname(SCRIPT_DIR)
BUILTIN_DATA = os.path.join(PLUGIN_ROOT, "data", "bots.json")

ICON_PRESETS = {
    "robot": ("󰚩", "Robot (Default)"),
    "sparkles": ("󱐋", "Sparkles / AI"),
    "brain": ("󰘦", "Neural Brain"),
    "prompt": ("󰅩", "Code / Prompt"),
    "bot": ("󱚡", "Modern Bot"),
    "chip": ("󰍛", "Processor / Chip"),
    "terminal": ("󰆍", "Terminal Cursor"),
    "alien": ("󰚥", "Alien Bot"),
}


def ensure_state_dir():
    os.makedirs(STATE_DIR, exist_ok=True)


def notify_desktop(title, message, icon="dialog-information"):
    try:
        subprocess.run(["notify-send", "-a", "Omabot", "-i", icon, title, message], check=False)
    except Exception:
        pass


def load_json_file(path, default=None):
    if default is None:
        default = []
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return default
    return default


def save_json_file(path, data):
    ensure_state_dir()
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def parse_frontmatter(content):
    metadata = {}
    body = content

    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            fm_text = parts[1].strip()
            body = parts[2].strip()
            in_integrations = False
            integrations_list = []

            for line in fm_text.splitlines():
                line_str = line.strip()
                if not line_str or line_str.startswith("#"):
                    continue

                if line.startswith("integrations:"):
                    in_integrations = True
                    integrations_list = []
                    continue

                if in_integrations:
                    if line.startswith("  - ") or line.startswith("- "):
                        val = line.split("-", 1)[1].strip().strip('"').strip("'")
                        if val:
                            integrations_list.append(val)
                        continue
                    else:
                        in_integrations = False
                        metadata["integrations"] = integrations_list

                if ":" in line:
                    key, val = line.split(":", 1)
                    key = key.strip()
                    val = val.strip().strip('"').strip("'")
                    metadata[key] = val

            if in_integrations and integrations_list:
                metadata["integrations"] = integrations_list

    return metadata, body


def sync_bots():
    ensure_state_dir()
    print("⏳ Synchronizing bot directory from botdirectory.ai...")

    with tempfile.TemporaryDirectory() as temp_dir:
        repo_dir = os.path.join(temp_dir, "repo")
        clone_cmd = [
            "git", "clone", "--depth", "1",
            "--filter=blob:none", "--sparse",
            UPSTREAM_REPO, repo_dir
        ]

        try:
            subprocess.run(clone_cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["git", "sparse-checkout", "set", "content/bots"], cwd=repo_dir, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"Error cloning repository: {e}")
            if os.path.exists(BUILTIN_DATA) and not os.path.exists(CACHE_FILE):
                shutil.copy(BUILTIN_DATA, CACHE_FILE)
            return

        bots_dir = os.path.join(repo_dir, "content", "bots")
        if not os.path.exists(bots_dir):
            print("Could not locate content/bots directory in upstream repo.")
            return

        bots = []
        for root_dir, _, files in os.walk(bots_dir):
            for file in sorted(files):
                if file.endswith(".md") and not file.startswith("_"):
                    file_path = os.path.join(root_dir, file)
                    slug = os.path.splitext(file)[0]
                    try:
                        with open(file_path, "r", encoding="utf-8") as f:
                            content = f.read()
                        meta, prompt = parse_frontmatter(content)
                        name = meta.get("title", slug.replace("-", " ").title())
                        category = meta.get("category", "General")
                        contributor = meta.get("contributor", "")
                        contributor_url = meta.get("contributorUrl", "")
                        integrations = meta.get("integrations", [])

                        bots.append({
                            "name": name,
                            "slug": slug,
                            "category": category,
                            "contributor": contributor,
                            "contributor_url": contributor_url,
                            "integrations": integrations,
                            "prompt": prompt
                        })
                    except Exception as err:
                        print(f"Skipping {file}: {err}")

        if bots:
            save_json_file(CACHE_FILE, bots)
            if os.path.exists(BUILTIN_DATA):
                try:
                    with open(BUILTIN_DATA, "w", encoding="utf-8") as f:
                        json.dump(bots, f, indent=2, ensure_ascii=False)
                except Exception:
                    pass
            print(f"✨ Successfully synced {len(bots)} bot prompts to {CACHE_FILE}!")
            notify_desktop("Omabot Directory Synced", f"{len(bots)} bots updated from botdirectory.ai", "emblem-default")
        else:
            print("No bot files found during synchronization.")


def load_all_bots():
    ensure_state_dir()
    bots = []
    if os.path.exists(CACHE_FILE):
        bots = load_json_file(CACHE_FILE, [])
    elif os.path.exists(BUILTIN_DATA):
        bots = load_json_file(BUILTIN_DATA, [])

    customs = load_json_file(CUSTOM_BOTS_FILE, [])
    for c in customs:
        c["isCustom"] = True
    return bots + customs


def copy_by_slug(slug_or_name):
    bots = load_all_bots()
    target = None
    for b in bots:
        if b.get("slug") == slug_or_name or b.get("name", "").lower() == slug_or_name.lower():
            target = b
            break

    if not target:
        print(f"Bot '{slug_or_name}' not found.")
        sys.exit(1)

    prompt = target.get("prompt", "")
    try:
        proc = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE)
        proc.communicate(input=prompt.encode("utf-8"))
        print(f"📋 Copied prompt for '{target.get('name')}' to clipboard!")
        notify_desktop(f"Prompt Copied: {target.get('name')}", "Prompt copied to clipboard!", "edit-copy")
        record_recent(target.get("slug", target.get("name")))
    except Exception as e:
        print(f"Could not copy to clipboard: {e}")
        print("\nPrompt content:\n" + prompt)


def record_recent(slug):
    recents = load_json_file(RECENTS_FILE, [])
    if slug in recents:
        recents.remove(slug)
    recents.insert(0, slug)
    save_json_file(RECENTS_FILE, recents[:20])


def toggle_favorite(slug):
    favs = load_json_file(FAVORITES_FILE, [])
    if slug in favs:
        favs.remove(slug)
        print(f"☆ Removed from favorites: {slug}")
        notify_desktop("Favorite Removed", f"Removed '{slug}' from favorites", "starred")
    else:
        favs.append(slug)
        print(f"⭐ Added to favorites: {slug}")
        notify_desktop("Favorite Added", f"Added '{slug}' to favorites", "starred")
    save_json_file(FAVORITES_FILE, favs)


def add_custom_bot(name, category, prompt, author="User"):
    customs = load_json_file(CUSTOM_BOTS_FILE, [])
    slug = name.lower().replace(" ", "-").replace("/", "-")
    
    customs = [c for c in customs if c.get("slug") != slug]
    customs.append({
        "name": name,
        "slug": slug,
        "category": category or "Custom",
        "contributor": author,
        "contributor_url": "",
        "integrations": [],
        "prompt": prompt,
        "isCustom": True
    })
    save_json_file(CUSTOM_BOTS_FILE, customs)
    print(f"✨ Custom bot '{name}' added successfully! (slug: {slug})")
    notify_desktop("Custom Bot Added", f"'{name}' added to your personal library", "document-new")


def remove_custom_bot(slug):
    customs = load_json_file(CUSTOM_BOTS_FILE, [])
    filtered = [c for c in customs if c.get("slug") != slug]
    if len(filtered) < len(customs):
        save_json_file(CUSTOM_BOTS_FILE, filtered)
        print(f"🗑️ Removed custom bot '{slug}'")
    else:
        print(f"Custom bot '{slug}' not found.")


def view_bot_info(slug_or_name):
    bots = load_all_bots()
    target = None
    for b in bots:
        if b.get("slug") == slug_or_name or b.get("name", "").lower() == slug_or_name.lower():
            target = b
            break

    if not target:
        print(f"Bot '{slug_or_name}' not found.")
        sys.exit(1)

    print("\n" + "=" * 60)
    print(f"🤖 \033[1m{target.get('name')}\033[0m")
    print(f"🏷️  Category: {target.get('category')}")
    if target.get("contributor"):
        url = f" ({target.get('contributor_url')})" if target.get("contributor_url") else ""
        print(f"👤 Author: @{target.get('contributor')}{url}")
    if target.get("integrations"):
        print(f"🛠️  Integrations: {', '.join(target.get('integrations'))}")
    print("-" * 60)
    print(f"{target.get('prompt')}")
    print("=" * 60 + "\n")


def list_icons():
    print("\n🎨 Available Omabot Bar Icon Styles:")
    print("=" * 60)
    for k, (glyph, desc) in ICON_PRESETS.items():
        print(f"• \033[1m{k:<12}\033[0m : {glyph}  ({desc})")
    print("=" * 60)
    print("Commands:")
    print("  omabot set-icon <style>     Set preset bar icon (e.g. omabot set-icon sparkles)")
    print("  omabot set-icon <glyph>     Set custom Unicode/Nerd Font character\n")


def set_bar_icon(icon_name):
    if not os.path.exists(SHELL_CONFIG_FILE):
        print(f"Error: Shell config not found at {SHELL_CONFIG_FILE}")
        return

    try:
        with open(SHELL_CONFIG_FILE, "r", encoding="utf-8") as f:
            config = json.load(f)

        layout = config.get("bar", {}).get("layout", {})
        found = False
        for sec in ["left", "center", "right"]:
            items = layout.get(sec, [])
            for item in items:
                if isinstance(item, dict) and item.get("id") == "dorneles.omabot":
                    if icon_name in ICON_PRESETS:
                        item["iconStyle"] = icon_name
                        item.pop("customIcon", None)
                        glyph, desc = ICON_PRESETS[icon_name]
                        print(f"✨ Set Omabot bar icon to '{icon_name}' ({glyph} - {desc})")
                    else:
                        item["customIcon"] = icon_name
                        print(f"✨ Set Omabot bar icon to custom character: {icon_name}")
                    found = True
                    break
            if found:
                break

        if not found:
            print("Adding dorneles.omabot to right section of shell.json...")
            if "right" not in layout:
                layout["right"] = []
            entry = {"id": "dorneles.omabot"}
            if icon_name in ICON_PRESETS:
                entry["iconStyle"] = icon_name
            else:
                entry["customIcon"] = icon_name
            layout["right"].append(entry)

        with open(SHELL_CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2)

        # Notify running shell via IPC
        subprocess.run(["omarchy-shell", "dorneles.omabot", "setIcon", icon_name], capture_output=True)
    except Exception as e:
        print(f"Error updating shell.json: {e}")


def list_bots(category_filter=None):
    bots = load_all_bots()
    favs = set(load_json_file(FAVORITES_FILE, []))

    if category_filter:
        cat_lower = category_filter.lower()
        if cat_lower == "favorites" or cat_lower == "⭐ favorites":
            bots = [b for b in bots if (b.get("slug") in favs or b.get("name") in favs)]
        elif cat_lower == "recent" or cat_lower == "🕒 recent":
            recents = load_json_file(RECENTS_FILE, [])
            bot_map = {b.get("slug", b.get("name")): b for b in bots}
            bots = [bot_map[r] for r in recents if r in bot_map]
        elif cat_lower != "all":
            bots = [b for b in bots if b.get("category", "").lower() == cat_lower]

    print(f"\n🤖 Omabot Directory ({len(bots)} bots found):")
    print("=" * 60)
    for b in bots:
        slug = b.get("slug", b.get("name"))
        is_fav = "⭐ " if slug in favs else ""
        cat = b.get("category", "General")
        name = b.get("name", "Unknown")
        ints = f" [{', '.join(b.get('integrations', []))}]" if b.get("integrations") else ""
        prompt = b.get("prompt", "").replace("\n", " ")
        if len(prompt) > 80:
            prompt = prompt[:77] + "..."
        print(f"• {is_fav}\033[1m{name}\033[0m \033[90m({cat}){ints}\033[0m")
        print(f"  \033[37m{prompt}\033[0m")
    print("=" * 60)


def search_bots(query):
    bots = load_all_bots()
    q = query.lower()
    matched = [
        b for b in bots
        if q in b.get("name", "").lower()
        or q in b.get("prompt", "").lower()
        or q in b.get("category", "").lower()
        or any(q in i.lower() for i in b.get("integrations", []))
    ]
    print(f"\n🔍 Search results for '{query}' ({len(matched)} matches):")
    print("-" * 60)
    for b in matched:
        ints = f" [{', '.join(b.get('integrations', []))}]" if b.get("integrations") else ""
        print(f"• \033[1m{b.get('name')}\033[0m ({b.get('category')}){ints} - slug: {b.get('slug')}")
        preview = b.get("prompt", "").replace("\n", " ")[:100]
        print(f"  {preview}...")
    print("-" * 60)


def open_source():
    try:
        subprocess.Popen(["xdg-open", SOURCE_REPO], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"🌐 Opening {SOURCE_REPO} in browser...")
    except Exception as e:
        print(f"Could not open browser: {e}")


def main():
    parser = argparse.ArgumentParser(description="omabot: AI Bot Directory CLI")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("sync", help="Sync latest bots from botdirectory.ai")
    
    list_p = subparsers.add_parser("list", help="List all bots")
    list_p.add_argument("--category", "-c", default="All", help="Filter by category (or 'favorites', 'recent')")

    search_p = subparsers.add_parser("search", help="Search bots")
    search_p.add_argument("query", help="Search keyword")

    copy_p = subparsers.add_parser("copy", help="Copy bot prompt to clipboard")
    copy_p.add_argument("slug", help="Bot slug or name")

    fav_p = subparsers.add_parser("fav", help="Toggle favorite for a bot")
    fav_p.add_argument("slug", help="Bot slug or name")

    subparsers.add_parser("favs", help="List favorite bots")
    subparsers.add_parser("recents", help="List recently copied bots")

    info_p = subparsers.add_parser("info", help="View full details and prompt of a bot")
    info_p.add_argument("slug", help="Bot slug or name")

    subparsers.add_parser("icons", help="List available bar icon styles")
    
    icon_p = subparsers.add_parser("set-icon", help="Set the bar icon style")
    icon_p.add_argument("style", help="Icon style (robot, sparkles, brain, prompt, bot, chip, terminal, alien) or custom glyph")

    add_p = subparsers.add_parser("add", help="Add a custom bot")
    add_p.add_argument("name", help="Bot name")
    add_p.add_argument("--category", "-c", default="Custom", help="Category")
    add_p.add_argument("--prompt", "-p", required=True, help="Prompt text")
    add_p.add_argument("--author", "-a", default="User", help="Author name")

    rm_p = subparsers.add_parser("remove-custom", help="Remove a custom bot")
    rm_p.add_argument("slug", help="Custom bot slug")

    subparsers.add_parser("open", help="Open source repository in browser")

    args = parser.parse_args()

    if args.command == "sync":
        sync_bots()
    elif args.command == "list":
        list_bots(args.category)
    elif args.command == "search":
        search_bots(args.query)
    elif args.command == "copy":
        copy_by_slug(args.slug)
    elif args.command == "fav":
        toggle_favorite(args.slug)
    elif args.command == "favs":
        list_bots("favorites")
    elif args.command == "recents":
        list_bots("recent")
    elif args.command == "info":
        view_bot_info(args.slug)
    elif args.command == "icons":
        list_icons()
    elif args.command == "set-icon":
        set_bar_icon(args.style)
    elif args.command == "add":
        add_custom_bot(args.name, args.category, args.prompt, args.author)
    elif args.command == "remove-custom":
        remove_custom_bot(args.slug)
    elif args.command == "open":
        open_source()
    else:
        ensure_state_dir()
        if not os.path.exists(CACHE_FILE) and os.path.exists(BUILTIN_DATA):
            shutil.copy(BUILTIN_DATA, CACHE_FILE)
        list_bots()


if __name__ == "__main__":
    main()
