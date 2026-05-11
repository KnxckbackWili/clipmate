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
SECRET = os.environ.get("CLIPMATE_SECRET", "")
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


def encryption_key() -> bytes:
    return hashlib.sha256(SECRET.encode("utf-8")).digest()


def encrypt_text(text: str) -> str:
    if not SECRET:
        return text
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        fail("CLIPMATE_SECRET requires: python3 -m pip install cryptography")

    nonce = os.urandom(12)
    cipher = AESGCM(encryption_key()).encrypt(nonce, text.encode("utf-8"), None)
    return json.dumps(
        {
            "v": 1,
            "alg": "AES-256-GCM-SHA256",
            "data": __import__("base64").b64encode(nonce + cipher).decode("ascii"),
        },
        separators=(",", ":"),
    )


def decrypt_text(payload: str) -> str:
    if not SECRET:
        return payload
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        fail("CLIPMATE_SECRET requires: python3 -m pip install cryptography")

    envelope = json.loads(payload)
    if envelope.get("v") != 1 or envelope.get("alg") != "AES-256-GCM-SHA256":
        raise ValueError("encrypted payload requires the same CLIPMATE_SECRET")
    combined = __import__("base64").b64decode(envelope["data"])
    nonce, cipher = combined[:12], combined[12:]
    return AESGCM(encryption_key()).decrypt(nonce, cipher, None).decode("utf-8")


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
    payload = encrypt_text(text)
    request(
        "PUT",
        f"/v1/rooms/{room}/clip",
        {"text": payload, "device": DEVICE, "hash": sha(payload)},
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
                remote_text = decrypt_text(remote.get("text", ""))
                remote_hash = sha(remote_text)
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
