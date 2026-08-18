#!/usr/bin/env python3
"""
omabot-sync.py — AI Bot Directory Synchronizer & Power CLI for Omarchy
Data source: https://github.com/elie222/botdirectory.ai
"""

import sys
import os
import json
import urllib.request
import urllib.parse
import subprocess
import argparse
import tempfile
import glob
import shutil

STATE_DIR = os.path.expanduser("~/.local/state/omarchy/omabot")
CACHE_FILE = os.path.join(STATE_DIR, "bots.json")
FAVORITES_FILE = os.path.join(STATE_DIR, "favorites.json")
RECENTS_FILE = os.path.join(STATE_DIR, "recents.json")
CUSTOM_BOTS_FILE = os.path.join(STATE_DIR, "custom_bots.json")
BUILTIN_DATA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "bots.json")
SOURCE_REPO = "https://github.com/elie222/botdirectory.ai"


def ensure_state_dir():
    os.makedirs(STATE_DIR, exist_ok=True)


def load_json_file(path, fallback=None):
    if fallback is None:
        fallback = []
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return fallback


def save_json_file(path, data):
    ensure_state_dir()
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def load_all_bots():
    bots = load_json_file(CACHE_FILE, None)
    if bots is None:
        bots = load_json_file(BUILTIN_DATA, [])
    custom = load_json_file(CUSTOM_BOTS_FILE, [])
    for c in custom:
        c["isCustom"] = True
    return bots + custom


def parse_frontmatter(content, slug):
    name = slug.replace("-", " ").title()
    category = "General"
    contributor = ""
    contributor_url = ""
    integrations = []
    prompt = ""

    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            fm_text = parts[1]
            prompt = parts[2].strip()
            for line in fm_text.splitlines():
                line = line.strip()
                if line.startswith("name:"):
                    name = line.split("name:", 1)[1].strip().strip("\"'")
                elif line.startswith("category:"):
                    category = line.split("category:", 1)[1].strip().strip("\"'")
                elif line.startswith("contributor:"):
                    contributor = line.split("contributor:", 1)[1].strip().strip("\"'")
                elif line.startswith("contributor_url:"):
                    contributor_url = line.split("contributor_url:", 1)[1].strip().strip("\"'")
                elif line.startswith("integrations:"):
                    raw_ints = line.split("integrations:", 1)[1].strip()
                    raw_ints = raw_ints.strip("[]").replace("\"", "").replace("'", "")
                    integrations = [i.strip() for i in raw_ints.split(",") if i.strip()]
    else:
        prompt = content.strip()

    return {
        "slug": slug,
        "name": name,
        "category": category or "General",
        "contributor": contributor,
        "contributor_url": contributor_url,
        "integrations": integrations,
        "prompt": prompt,
    }


def sync_bots():
    ensure_state_dir()
    print(f"🔄 Syncing bot directory from {SOURCE_REPO}...")

    tmp_dir = tempfile.mkdtemp()
    try:
        cmd = ["git", "clone", "--depth=1", SOURCE_REPO, tmp_dir]
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25)
        if res.returncode != 0:
            raise RuntimeError("Git clone failed")

        bot_files = glob.glob(os.path.join(tmp_dir, "bots", "*.md"))
        if not bot_files:
            raise RuntimeError("No bot files found")

        bots = []
        for path in bot_files:
            slug = os.path.basename(path).replace(".md", "")
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            parsed = parse_frontmatter(content, slug)
            bots.append(parsed)

        bots.sort(key=lambda x: x.get("name", "").lower())

        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(bots, f, indent=2, ensure_ascii=False)

        print(f"✅ Successfully synced {len(bots)} bots to {CACHE_FILE}")
        return True

    except Exception as e:
        print(f"⚠️ Network sync failed ({e}). Keeping existing cache.")
        if not os.path.exists(CACHE_FILE) and os.path.exists(BUILTIN_DATA):
            shutil.copy(BUILTIN_DATA, CACHE_FILE)
        return False
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def copy_to_clipboard(text, bot_name=None):
    if not text:
        return False
    copied = False

    # Try wl-copy (Wayland)
    try:
        p = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p.communicate(input=text.encode("utf-8"))
        if p.returncode == 0:
            copied = True
    except FileNotFoundError:
        pass

    # Try xclip (X11)
    if not copied:
        try:
            p = subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
            p.communicate(input=text.encode("utf-8"))
            if p.returncode == 0:
                copied = True
        except FileNotFoundError:
            pass

    # Send desktop notification if available
    if copied and bot_name:
        try:
            title = "Omabot Prompt Copied"
            msg = f"'{bot_name}' prompt copied to clipboard ({len(text)} chars)"
            subprocess.Popen(["notify-send", title, msg, "-i", "dialog-information", "-a", "Omabot"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    return copied


def record_recent(slug):
    recents = load_json_file(RECENTS_FILE, [])
    if slug in recents:
        recents.remove(slug)
    recents.insert(0, slug)
    save_json_file(RECENTS_FILE, recents[:20])


def toggle_favorite(slug):
    favorites = load_json_file(FAVORITES_FILE, [])
    if slug in favorites:
        favorites.remove(slug)
        action = "Removed from"
    else:
        favorites.append(slug)
        action = "Added to"
    save_json_file(FAVORITES_FILE, favorites)
    print(f"⭐ {action} favorites: {slug}")


def copy_by_slug(slug_or_name):
    bots = load_all_bots()
    target = None
    slug_q = slug_or_name.lower().strip()
    for b in bots:
        if b.get("slug", "").lower() == slug_q or b.get("name", "").lower() == slug_q:
            target = b
            break

    if not target:
        for b in bots:
            if slug_q in b.get("slug", "").lower() or slug_q in b.get("name", "").lower():
                target = b
                break

    if target:
        prompt = target.get("prompt", "")
        slug = target.get("slug", target.get("name"))
        if copy_to_clipboard(prompt, target.get("name")):
            record_recent(slug)
            print(f"📋 Copied prompt for '{target.get('name')}' to clipboard!")
        else:
            print(f"Prompt for '{target.get('name')}':\n\n{prompt}")
    else:
        print(f"❌ Bot '{slug_or_name}' not found.")


def add_custom_bot(name, category, prompt, contributor=None):
    custom = load_json_file(CUSTOM_BOTS_FILE, [])
    slug = name.lower().replace(" ", "-").replace("/", "-")
    
    new_bot = {
        "slug": slug,
        "name": name,
        "category": category or "Custom",
        "contributor": contributor or "User",
        "contributor_url": "",
        "integrations": [],
        "prompt": prompt.strip()
    }
    
    # Replace if exists
    custom = [c for c in custom if c.get("slug") != slug]
    custom.append(new_bot)
    save_json_file(CUSTOM_BOTS_FILE, custom)
    print(f"✨ Custom bot '{name}' added successfully! (slug: {slug})")


def remove_custom_bot(slug):
    custom = load_json_file(CUSTOM_BOTS_FILE, [])
    before = len(custom)
    custom = [c for c in custom if c.get("slug") != slug and c.get("name") != slug]
    if len(custom) < before:
        save_json_file(CUSTOM_BOTS_FILE, custom)
        print(f"🗑️ Removed custom bot '{slug}'")
    else:
        print(f"❌ Custom bot '{slug}' not found.")


def view_bot_info(slug_or_name):
    bots = load_all_bots()
    target = None
    slug_q = slug_or_name.lower().strip()
    for b in bots:
        if b.get("slug", "").lower() == slug_q or b.get("name", "").lower() == slug_q:
            target = b
            break
            
    if not target:
        for b in bots:
            if slug_q in b.get("slug", "").lower() or slug_q in b.get("name", "").lower():
                target = b
                break

    if not target:
        print(f"❌ Bot '{slug_or_name}' not found.")
        return

    print("\n" + "=" * 60)
    print(f"🤖 \033[1m{target.get('name')}\033[0m")
    print(f"🏷️  Category: \033[36m{target.get('category', 'General')}\033[0m")
    if target.get("contributor"):
        print(f"👤 Author: \033[33m@{target.get('contributor')}\033[0m ({target.get('contributor_url', '')})")
    if target.get("integrations"):
        print(f"🛠️  Integrations: {', '.join(target.get('integrations'))}")
    print("-" * 60)
    print(f"{target.get('prompt')}")
    print("=" * 60 + "\n")


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
