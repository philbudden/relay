#!/usr/bin/env python3
"""
Gitea GitHub Mirror Sync

Mirrors all repos owned by GITHUB_USER into Gitea as pull mirrors.
Idempotent: repos that already exist in Gitea are skipped.

Required environment variables:
  GITHUB_TOKEN    - GitHub Personal Access Token (repo scope)
  GITHUB_USER     - GitHub username whose repos to mirror
  GITEA_TOKEN     - Gitea API token
  GITEA_URL       - Gitea base URL (default: http://localhost:3000)
  MIRROR_INTERVAL - Gitea mirror poll interval (default: 6h0m0s)
"""

import json
import os
import sys
import urllib.error
import urllib.request

GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
GITHUB_USER = os.environ["GITHUB_USER"]
GITEA_TOKEN = os.environ["GITEA_TOKEN"]
GITEA_URL = os.environ.get("GITEA_URL", "http://localhost:3000").rstrip("/")
MIRROR_INTERVAL = os.environ.get("MIRROR_INTERVAL", "6h0m0s")


def github_get(path):
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        headers={
            "Authorization": f"token {GITHUB_TOKEN}",
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "gitea-github-sync/1.0",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def gitea_request(method, path, data=None):
    url = f"{GITEA_URL}/api/v1{path}"
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"token {GITEA_TOKEN}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read()), resp.status
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read()), e.code
        except Exception:
            return {}, e.code


def get_gitea_user():
    data, status = gitea_request("GET", "/user")
    if status != 200:
        print(f"ERROR: Cannot authenticate to Gitea: HTTP {status}", file=sys.stderr)
        print(f"       Check GITEA_TOKEN and GITEA_URL={GITEA_URL}", file=sys.stderr)
        sys.exit(1)
    return data


def get_github_repos():
    """Return all repos owned by GITHUB_USER (paginated)."""
    repos = []
    page = 1
    while True:
        page_repos = github_get(
            f"/user/repos?type=owner&affiliation=owner&per_page=100&page={page}"
        )
        if not page_repos:
            break
        repos.extend(page_repos)
        if len(page_repos) < 100:
            break
        page += 1
    return repos


def get_gitea_repos(uid):
    """Return set of repo names already in Gitea for this user."""
    repos = set()
    page = 1
    while True:
        data, status = gitea_request(
            "GET", f"/repos/search?limit=50&page={page}&uid={uid}"
        )
        if status != 200:
            break
        items = data.get("data", [])
        if not items:
            break
        for r in items:
            repos.add(r["name"])
        if len(items) < 50:
            break
        page += 1
    return repos


def create_mirror(uid, repo):
    """Create a Gitea pull mirror from a GitHub repo."""
    payload = {
        "clone_addr": repo["clone_url"],
        "auth_token": GITHUB_TOKEN,
        "uid": uid,
        "repo_name": repo["name"],
        "mirror": True,
        "private": repo["private"],
        "description": repo.get("description") or "",
        "mirror_interval": MIRROR_INTERVAL,
    }
    return gitea_request("POST", "/repos/migrate", payload)


def main():
    # Authenticate to Gitea and get user info
    gitea_user = get_gitea_user()
    uid = gitea_user["id"]
    gitea_login = gitea_user["login"]
    print(f"Gitea: authenticated as '{gitea_login}' (uid={uid})")

    # List GitHub repos
    print(f"GitHub: fetching repos for '{GITHUB_USER}'...")
    github_repos = get_github_repos()
    print(f"GitHub: found {len(github_repos)} owned repos")

    # List existing Gitea repos
    existing = get_gitea_repos(uid)
    print(f"Gitea:  {len(existing)} repos already mirrored")

    created = 0
    skipped = 0
    errors = 0

    for repo in github_repos:
        name = repo["name"]
        if name in existing:
            print(f"  SKIP   {name}")
            skipped += 1
        else:
            result, status = create_mirror(uid, repo)
            if status in (200, 201):
                visibility = "private" if repo["private"] else "public"
                print(f"  CREATE {name} ({visibility})")
                created += 1
            else:
                print(
                    f"  ERROR  {name}: HTTP {status} - {result.get('message', result)}",
                    file=sys.stderr,
                )
                errors += 1

    print(f"\nDone: {created} created, {skipped} skipped, {errors} errors")
    if errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
