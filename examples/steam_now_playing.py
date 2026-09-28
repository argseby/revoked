#!/usr/bin/env python3
"""Mirror your current Steam game into a revoked vault record and share it.

Polls the Steam Web API for what you are playing and keeps one vault record
up to date, e.g.:

    Hunt: Showdown - last edited 14:26
    Currently not playing a game - last edited 15:02

On first run it creates the record, uploads this script itself as a second
(file) vault record, and creates one share link carrying both - then prints
the public link (and nothing else) on stdout. Status chatter goes to stderr,
so `$(python steam_now_playing.py --once)` is exactly the link.

Configuration (environment):

    REVOKED_URL       Base URL of your revoked server, e.g. https://vault.example.com
    REVOKED_API_KEY   An API key with scopes: record:read, record:create,
                      record:update, link:read, link:create, link:update
                      (Settings -> API keys in the app)
    REVOKED_WORKSPACE_ID  Only needed when the vault is completely empty -
                      normally the script reads the workspace id off any
                      existing record or link.
    STEAM_API_KEY     Steam Web API key, from https://steamcommunity.com/dev/apikey
    STEAM_ID          Your 64-bit Steam id (17 digits), or your vanity name -
                      the custom part of https://steamcommunity.com/id/<name>,
                      which the script resolves for you

Usage:

    python steam_now_playing.py             # poll forever (default every 60s)
    python steam_now_playing.py --once      # single check, for cron
    python steam_now_playing.py --interval 30
"""

import argparse
import json
import os
import secrets
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

RECORD_KEY = "steam-current-game"
RECORD_LABEL = "Now playing on Steam"
SCRIPT_KEY = "steam-now-playing-script"
SCRIPT_LABEL = "steam_now_playing.py"
LINK_LABEL = "Now playing on Steam"
NOT_PLAYING = "Currently not playing a game"

STEAM_API = "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/"
STEAM_VANITY_API = "https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/"


def env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"Missing required environment variable {name} (see --help)")
    return value


def log(message):
    print(message, file=sys.stderr, flush=True)


class RevokedClient:
    def __init__(self, base_url, api_key):
        self.base = base_url.rstrip("/")
        self.api_key = api_key

    def _call(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(
            self.base + path,
            data=data,
            method=method,
            headers={
                "X-API-Key": self.api_key,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as err:
            detail = err.read().decode(errors="replace")
            sys.exit(f"revoked API {method} {path} failed ({err.code}): {detail}")

    def _first(self, collection, filter_expr=None):
        params = {"perPage": 1}
        if filter_expr:
            params["filter"] = filter_expr
        query = urllib.parse.urlencode(params)
        result = self._call(
            "GET", f"/api/collections/{collection}/records?{query}"
        )
        items = result.get("items", [])
        return items[0] if items else None

    def workspace_id(self):
        # The access rules check the submitted record's workspace against the
        # key's before the server stamps anything, so a create must name it.
        # Any row the key can read carries it; an empty vault needs the env.
        for collection in ("records", "links"):
            row = self._first(collection)
            if row:
                return row["workspace"]
        from_env = os.environ.get("REVOKED_WORKSPACE_ID", "").strip()
        if from_env:
            return from_env
        sys.exit(
            "The vault is empty, so the workspace id cannot be discovered - "
            "set REVOKED_WORKSPACE_ID (visible in the app under Settings)."
        )

    def find_or_create_record(self):
        record = self._first("records", f"key='{RECORD_KEY}'")
        if record:
            return record
        log(f"Creating vault record '{RECORD_KEY}'")
        return self._call(
            "POST",
            "/api/collections/records/records",
            {
                "key": RECORD_KEY,
                "label": RECORD_LABEL,
                "value": f"{NOT_PLAYING} - last edited {time.strftime('%H:%M')}",
                "type": "text",
                "format": "default",
                "workspace": self.workspace_id(),
            },
        )

    def find_or_create_script_record(self):
        record = self._first("records", f"key='{SCRIPT_KEY}'")
        if record:
            return record
        log(f"Uploading this script as vault record '{SCRIPT_KEY}'")
        with open(__file__, "rb") as f:
            content = f.read()
        return self._upload(
            "/api/collections/records/records",
            fields={
                "key": SCRIPT_KEY,
                "label": SCRIPT_LABEL,
                "type": "file",
                "format": "default",
                "workspace": self.workspace_id(),
            },
            filename=os.path.basename(__file__),
            content=content,
        )

    def _upload(self, path, fields, filename, content):
        boundary = "----revoked-" + secrets.token_hex(12)
        parts = []
        for name, value in fields.items():
            parts.append(
                (
                    f"--{boundary}\r\n"
                    f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                    f"{value}\r\n"
                ).encode()
            )
        parts.append(
            (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="file"; '
                f'filename="{filename}"\r\n'
                f"Content-Type: application/octet-stream\r\n\r\n"
            ).encode()
            + content
            + b"\r\n"
        )
        parts.append(f"--{boundary}--\r\n".encode())
        request = urllib.request.Request(
            self.base + path,
            data=b"".join(parts),
            method="POST",
            headers={
                "X-API-Key": self.api_key,
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as err:
            detail = err.read().decode(errors="replace")
            sys.exit(f"revoked API POST {path} failed ({err.code}): {detail}")

    def find_or_create_link(self, record_ids):
        link = self._first("links", f"records~'{record_ids[0]}'")
        if link is None:
            # The slug is the only thing protecting the link, so it must carry
            # real entropy - never something guessable.
            alphabet = string.ascii_lowercase + string.digits
            slug = "".join(secrets.choice(alphabet) for _ in range(16))
            log(f"Creating share link /s/{slug}")
            return self._call(
                "POST",
                "/api/collections/links/records",
                {
                    "slug": slug,
                    "label": LINK_LABEL,
                    "records": record_ids,
                    "status": "active",
                    "workspace": self.workspace_id(),
                },
            )
        missing = [r for r in record_ids if r not in link.get("records", [])]
        if missing:
            log("Adding missing records to the existing share link")
            link = self._call(
                "PATCH",
                f"/api/collections/links/records/{link['id']}",
                {"records": link.get("records", []) + missing},
            )
        return link

    def set_record_value(self, record_id, value):
        self._call(
            "PATCH",
            f"/api/collections/records/records/{record_id}",
            {"value": value},
        )


def resolve_steam_id(steam_key, steam_id):
    """GetPlayerSummaries only takes the numeric 64-bit id; a vanity name
    (steamcommunity.com/id/<name>) must be resolved first."""
    if steam_id.isdigit():
        return steam_id
    query = urllib.parse.urlencode({"key": steam_key, "vanityurl": steam_id})
    try:
        with urllib.request.urlopen(
            f"{STEAM_VANITY_API}?{query}", timeout=30
        ) as response:
            result = json.load(response).get("response", {})
    except (urllib.error.URLError, json.JSONDecodeError) as err:
        sys.exit(f"Could not resolve Steam vanity name '{steam_id}': {err}")
    if result.get("success") != 1:
        sys.exit(
            f"Steam does not know the vanity name '{steam_id}' - use the "
            "17-digit steamid64 from your profile URL instead."
        )
    resolved = result["steamid"]
    log(f"Resolved Steam vanity name '{steam_id}' to {resolved}")
    return resolved


def current_steam_game(steam_key, steam_id):
    query = urllib.parse.urlencode({"key": steam_key, "steamids": steam_id})
    try:
        with urllib.request.urlopen(f"{STEAM_API}?{query}", timeout=30) as response:
            players = json.load(response).get("response", {}).get("players", [])
    except (urllib.error.URLError, json.JSONDecodeError) as err:
        log(f"Steam API unreachable, keeping last value: {err}")
        return None, False
    if not players:
        log("Steam returned no player for this id (private profile?)")
        return None, False
    return players[0].get("gameextrainfo"), True


def game_part(value):
    return value.rsplit(" - last edited ", 1)[0]


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--once", action="store_true", help="check once and exit")
    parser.add_argument(
        "--interval", type=int, default=60, help="poll interval in seconds"
    )
    args = parser.parse_args()

    client = RevokedClient(env("REVOKED_URL"), env("REVOKED_API_KEY"))
    steam_key = env("STEAM_API_KEY")
    steam_id = resolve_steam_id(steam_key, env("STEAM_ID"))

    record = client.find_or_create_record()
    script_record = client.find_or_create_script_record()
    link = client.find_or_create_link([record["id"], script_record["id"]])

    # The one thing on stdout: the public link.
    print(f"{client.base}/s/{link['slug']}", flush=True)

    last_game = game_part(record.get("value", ""))
    while True:
        game, ok = current_steam_game(steam_key, steam_id)
        if ok:
            text = game or NOT_PLAYING
            if text != last_game:
                stamp = time.strftime("%H:%M")
                client.set_record_value(record["id"], f"{text} - last edited {stamp}")
                log(f"Updated: {text} - last edited {stamp}")
                last_game = text
        if args.once:
            break
        time.sleep(args.interval)


if __name__ == "__main__":
    main()