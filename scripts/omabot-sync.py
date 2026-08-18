#!/usr/bin/env python3
"""
omabot-sync.py — AI Bot Directory Synchronizer & CLI for Omarchy
Data source: https://github.com/elie222/botdirectory.ai
"""

import sys
import os
import json
import urllib.request
import urllib.parse
import subprocess
import argparse

STATE_DIR = os.path.expanduser("~/.local/state/omarchy/omabot")
CACHE_FILE = os.path.join(STATE_DIR, "bots.json")
BUILTIN_DATA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "bots.json")
SOURCE_REPO = "https://github.com/elie222/botdirectory.ai"
GITHUB_API_TREE = "https://api.github.com/repos/elie222/botdirectory.ai/git/trees/main?recursive=1"
RAW_BASE_URL = "https://raw.githubusercontent.com/elie222/botdirectory.ai/main/"


def ensure_state_dir():
    os.makedirs(STATE_DIR, exist_ok=True)


def load_local_bots():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    if os.path.exists(BUILTIN_DATA):
        try:
            with open(BUILTIN_DATA, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return []


def parse_frontmatter(content, slug):
    name = slug.replace("-", " ").title()
    category = "General"
    contributor = ""
    contributor_url = ""
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
    else:
        prompt = content.strip()

    return {
        "slug": slug,
        "name": name,
        "category": category or "General",
        "contributor": contributor,
        "contributor_url": contributor_url,
        "prompt": prompt,
    }


def sync_bots():
    ensure_state_dir()
    print(f"🔄 Syncing bot directory from {SOURCE_REPO}...")

    # Load existing bots to preserve custom/featured items
    existing = load_local_bots()
    bots_dict = {b["slug"]: b for b in existing}

    try:
        req = urllib.request.Request(
            GITHUB_API_TREE,
            headers={"User-Agent": "omabot-sync/1.0", "Accept": "application/vnd.github.v3+json"},
        )
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        bot_paths = [
            item["path"]
            for item in data.get("tree", [])
            if item["path"].startswith("bots/") and item["path"].endswith(".md")
        ]

        print(f"📦 Found {len(bot_paths)} bot definitions. Updating...")
        updated_count = 0

        for path in bot_paths:
            slug = os.path.basename(path).replace(".md", "")
            raw_url = RAW_BASE_URL + urllib.parse.quote(path)
            try:
                r = urllib.request.Request(raw_url, headers={"User-Agent": "omabot-sync/1.0"})
                with urllib.request.urlopen(r, timeout=6) as r_resp:
                    content = r_resp.read().decode("utf-8", errors="ignore")
                    parsed = parse_frontmatter(content, slug)
                    bots_dict[slug] = parsed
                    updated_count += 1
            except Exception:
                continue

        all_bots = list(bots_dict.values())
        all_bots.sort(key=lambda x: x.get("name", "").lower())

        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(all_bots, f, indent=2, ensure_ascii=False)

        print(f"✅ Successfully synced {len(all_bots)} bots to {CACHE_FILE}")
        return True
    except Exception as e:
        print(f"⚠️ Network sync failed ({e}). Keeping existing cache.")
        if not os.path.exists(CACHE_FILE) and os.path.exists(BUILTIN_DATA):
            import shutil
            shutil.copy(BUILTIN_DATA, CACHE_FILE)
        return False


def copy_to_clipboard(text):
    if not text:
        return False
    # Try wl-copy (Wayland)
    try:
        p = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p.communicate(input=text.encode("utf-8"))
        if p.returncode == 0:
            return True
    except FileNotFoundError:
        pass

    # Try xclip (X11)
    try:
        p = subprocess.Popen(["xclip", "-selection", "clipboard"], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p.communicate(input=text.encode("utf-8"))
        if p.returncode == 0:
            return True
    except FileNotFoundError:
        pass

    # Try xsel
    try:
        p = subprocess.Popen(["xsel", "--clipboard", "--input"], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p.communicate(input=text.encode("utf-8"))
        if p.returncode == 0:
            return True
    except FileNotFoundError:
        pass

    return False


def list_bots(category_filter=None):
    bots = load_local_bots()
    if category_filter and category_filter.lower() != "all":
        bots = [b for b in bots if b.get("category", "").lower() == category_filter.lower()]

    print(f"\n🤖 Omabot Directory ({len(bots)} bots found):")
    print("=" * 60)
    for b in bots:
        cat = b.get("category", "General")
        name = b.get("name", "Unknown")
        prompt = b.get("prompt", "").replace("\n", " ")
        if len(prompt) > 80:
            prompt = prompt[:77] + "..."
        print(f"• \033[1m{name}\033[0m \033[90m[{cat}]\033[0m")
        print(f"  \033[37m{prompt}\033[0m")
    print("=" * 60)


def search_bots(query):
    bots = load_local_bots()
    q = query.lower()
    matched = [
        b for b in bots
        if q in b.get("name", "").lower()
        or q in b.get("prompt", "").lower()
        or q in b.get("category", "").lower()
    ]
    print(f"\n🔍 Search results for '{query}' ({len(matched)} matches):")
    print("-" * 60)
    for b in matched:
        print(f"• \033[1m{b.get('name')}\033[0m ({b.get('category')}) - slug: {b.get('slug')}")
        preview = b.get("prompt", "").replace("\n", " ")[:100]
        print(f"  {preview}...")
    print("-" * 60)


def copy_by_slug(slug_or_name):
    bots = load_local_bots()
    target = None
    slug_q = slug_or_name.lower().strip()
    for b in bots:
        if b.get("slug", "").lower() == slug_q or b.get("name", "").lower() == slug_q:
            target = b
            break

    if not target:
        # Partial match
        for b in bots:
            if slug_q in b.get("slug", "").lower() or slug_q in b.get("name", "").lower():
                target = b
                break

    if target:
        prompt = target.get("prompt", "")
        if copy_to_clipboard(prompt):
            print(f"📋 Copied prompt for '{target.get('name')}' to clipboard!")
        else:
            print(f"Prompt for '{target.get('name')}':\n\n{prompt}")
    else:
        print(f"❌ Bot '{slug_or_name}' not found.")


def open_source():
    try:
        subprocess.Popen(["xdg-open", SOURCE_REPO], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"🌐 Opening {SOURCE_REPO} in browser...")
    except Exception as e:
        print(f"Could not open browser: {e}")


def main():
    parser = argparse.ArgumentParser(description="omabot-sync: AI Bot Directory CLI")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("sync", help="Sync latest bots from botdirectory.ai")
    
    list_p = subparsers.add_parser("list", help="List all bots")
    list_p.add_argument("--category", "-c", default="All", help="Filter by category")

    search_p = subparsers.add_parser("search", help="Search bots")
    search_p.add_argument("query", help="Search keyword")

    copy_p = subparsers.add_parser("copy", help="Copy bot prompt to clipboard")
    copy_p.add_argument("slug", help="Bot slug or name")

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
    elif args.command == "open":
        open_source()
    else:
        ensure_state_dir()
        if not os.path.exists(CACHE_FILE) and os.path.exists(BUILTIN_DATA):
            import shutil
            shutil.copy(BUILTIN_DATA, CACHE_FILE)
        list_bots()


if __name__ == "__main__":
    main()
