#!/usr/bin/env python3
"""Writes a ZenPM package source (zenpm/manifest.json + zenpm/versions.json).

Users add https://raw.githubusercontent.com/<owner>/<repo>/main/zenpm/ as a
source in ZenPM. Format: https://github.com/xZenLabs/zen-pm docs/architecture/repository-index.md

Env: GITHUB_REPOSITORY (owner/repo), GITHUB_TOKEN (optional, avoids rate limits).
"""
import json
import os
import urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "helloparthshah/dailygames.koplugin")
OWNER = REPO.split("/")[0]
ASSET = "dailygames.koplugin.zip"
RAW = f"https://raw.githubusercontent.com/{REPO}/main"
BASE = f"{RAW}/zenpm/"
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "zenpm")


def github(path):
    req = urllib.request.Request(f"https://api.github.com/repos/{REPO}{path}",
                                 headers={"Accept": "application/vnd.github+json"})
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main():
    releases = []
    for rel in github("/releases?per_page=100"):
        if rel.get("draft"):
            continue
        assets = [
            {"name": a["name"], "url": a["browser_download_url"], "size": int(a["size"]),  # ZenPM wants a number
             **({"digest": a["digest"]} if a.get("digest") else {})}
            for a in rel.get("assets", []) if a["name"] == ASSET
        ]
        if assets:
            releases.append({"tag_name": rel["tag_name"], "name": rel.get("name") or rel["tag_name"],
                             "prerelease": bool(rel.get("prerelease")), "assets": assets,
                             "published_at": rel.get("published_at")})
    stable = [r for r in releases if not r["prerelease"]]
    if not stable:
        raise SystemExit("no stable release with " + ASSET)
    latest = stable[0]

    package = {
        "id": "dailygames",
        "name": "Daily Games",
        "version": latest["tag_name"].lstrip("v"),
        "description": "Daily puzzle games: NYT Wordle, Connections, Strands, Mini and Daily Crossword, "
                       "plus Krillion trivia. Adds itself to the ZenOS App Launcher.",
        "author": OWNER,
        "category": "games",
        "platforms": ["koreader"],
        "dependencies": [],
        "size": latest["assets"][0]["size"],
        "source": f"https://github.com/{REPO}",
        "source_asset": ASSET,
        "source_type": "release",
        "published_at": latest["published_at"],
        "readme_url": f"{RAW}/README.md",
        "versions_url": f"{BASE}versions.json",
    }
    manifest = {
        "schema_version": "1",
        "repo": {"id": "dailygames", "name": "Daily Games", "url": BASE},
        "packages": [package],
    }
    versions = {"releases": [{k: v for k, v in r.items() if k != "published_at"} for r in releases]}

    os.makedirs(OUT, exist_ok=True)
    for name, data in (("manifest.json", manifest), ("versions.json", versions)):
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
    print(f"ZenPM source updated for {latest['tag_name']}: {BASE}")


if __name__ == "__main__":
    main()
