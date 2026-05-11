#!/usr/bin/env python3
import hashlib
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


SERVER = os.environ.get("CLIPMATE_SERVER", "").rstrip("/")
TOKEN = os.environ.get("CLIPMATE_TOKEN", "")
ROOM = os.environ.get("CLIPMATE_ROOM", "default")
DEVICE = os.environ.get("CLIPMATE_DEVICE", socket.gethostname())
POLL_SECONDS = float(os.environ.get("CLIPMATE_POLL_SECONDS", "0.8"))
MAX_CHARS = int(os.environ.get("CLIPMATE_MAX_CHARS", "524288"))
PAUSE_FILE = os.environ.get(
    "CLIPMATE_PAUSE_FILE",
    os.path.expanduser("~/.clipmate-paused"),
)


def fail(message: str) -> None:
    print(f"clipmate: {message}", file=sys.stderr)
    sys.exit(1)


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def pbpaste() -> str:
    try:
        return subprocess.check_output(["pbpaste"], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""


def pbcopy(text: str) -> None:
    subprocess.run(["pbcopy"], input=text, text=True, check=True)


def is_paused() -> bool:
    return os.path.exists(PAUSE_FILE)


def request(method: str, path: str, payload: dict | None = None) -> dict | None:
    data = None
    headers = {"Authorization": f"Bearer {TOKEN}"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(f"{SERVER}{path}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=8) as response:
        raw = response.read()
        if not raw or raw == b"null":
            return None
        return json.loads(raw.decode("utf-8"))


def push_clip(text: str, digest: str) -> None:
    room = urllib.parse.quote(ROOM, safe="")
    request(
        "PUT",
        f"/v1/rooms/{room}/clip",
        {"text": text, "device": DEVICE, "hash": digest},
    )


def pull_clip() -> dict | None:
    room = urllib.parse.quote(ROOM, safe="")
    return request("GET", f"/v1/rooms/{room}/clip")


def heartbeat(local_paused: bool) -> dict | None:
    room = urllib.parse.quote(ROOM, safe="")
    device = urllib.parse.quote(DEVICE, safe="")
    return request(
        "POST",
        f"/v1/rooms/{room}/devices/{device}/heartbeat",
        {"local_paused": local_paused},
    )


def main() -> None:
    if not SERVER:
        fail("CLIPMATE_SERVER is required, for example https://clip.example.com")
    if not TOKEN:
        fail("CLIPMATE_TOKEN is required")

    last_seen_hash = sha(pbpaste())
    last_applied_remote_hash = last_seen_hash
    print(f"clipmate: syncing room '{ROOM}' as '{DEVICE}' via {SERVER}")

    while True:
        try:
            local_paused = is_paused()
            device_state = heartbeat(local_paused)
            remote_enabled = True if not device_state else bool(device_state.get("enabled", True))

            if local_paused or not remote_enabled:
                last_seen_hash = sha(pbpaste())
                last_applied_remote_hash = last_seen_hash
                time.sleep(POLL_SECONDS)
                continue

            local_text = pbpaste()
            local_hash = sha(local_text)

            if (
                local_text
                and local_hash != last_seen_hash
                and local_hash != last_applied_remote_hash
            ):
                if len(local_text) <= MAX_CHARS:
                    push_clip(local_text, local_hash)
                    last_seen_hash = local_hash

            remote = pull_clip()
            if remote and remote.get("device") != DEVICE:
                remote_text = remote.get("text", "")
                remote_hash = remote.get("hash") or sha(remote_text)
                current_hash = sha(pbpaste())
                if remote_text and remote_hash != current_hash:
                    pbcopy(remote_text)
                    last_applied_remote_hash = remote_hash
                    last_seen_hash = remote_hash

        except urllib.error.HTTPError as exc:
            print(f"clipmate: server returned HTTP {exc.code}", file=sys.stderr)
        except Exception as exc:
            print(f"clipmate: {exc}", file=sys.stderr)

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
