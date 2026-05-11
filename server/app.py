import os
import time
from typing import Dict, Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field


APP_TOKEN = os.environ.get("CLIPMATE_TOKEN", "")
MAX_BYTES = int(os.environ.get("CLIPMATE_MAX_BYTES", str(512 * 1024)))

app = FastAPI(title="ClipMate Relay", version="0.1.0")


class ClipPut(BaseModel):
    text: str = Field(default="", max_length=MAX_BYTES)
    device: str = Field(default="unknown", max_length=80)
    hash: str = Field(default="", max_length=128)


class ClipState(BaseModel):
    text: str
    device: str
    hash: str
    updated_at: float


class ClipMeta(BaseModel):
    device: str
    hash: str
    updated_at: float
    bytes: int


class DeviceHeartbeat(BaseModel):
    local_paused: bool = False


class DeviceSettings(BaseModel):
    enabled: bool = True


class DeviceState(BaseModel):
    device: str
    enabled: bool = True
    local_paused: bool = False
    last_seen_at: float


clips: Dict[str, ClipState] = {}
devices: Dict[str, Dict[str, DeviceState]] = {}


INDEX_HTML = """
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ClipMate</title>
  <style>
    :root {
      color-scheme: light dark;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f7f7f4;
      color: #202124;
    }
    body {
      margin: 0;
      min-height: 100vh;
      background: #f7f7f4;
    }
    main {
      width: min(960px, calc(100% - 32px));
      margin: 0 auto;
      padding: 32px 0;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 24px;
    }
    h1 {
      margin: 0;
      font-size: 28px;
      letter-spacing: 0;
    }
    .muted {
      color: #6f736d;
      font-size: 14px;
    }
    .panel {
      border: 1px solid #d8d9d3;
      border-radius: 8px;
      background: #ffffff;
      padding: 18px;
      margin-bottom: 16px;
    }
    .controls {
      display: grid;
      grid-template-columns: 1fr 1fr auto;
      gap: 10px;
      align-items: end;
    }
    label {
      display: grid;
      gap: 6px;
      font-size: 13px;
      color: #52564f;
    }
    input {
      min-width: 0;
      border: 1px solid #c7c9c0;
      border-radius: 6px;
      padding: 10px 12px;
      font: inherit;
      background: #fff;
      color: #202124;
    }
    button {
      border: 1px solid #1e5f4f;
      border-radius: 6px;
      padding: 10px 14px;
      font: inherit;
      color: #fff;
      background: #24735f;
      cursor: pointer;
      white-space: nowrap;
    }
    button.secondary {
      color: #202124;
      background: #f1f2ed;
      border-color: #c7c9c0;
    }
    button.danger {
      background: #9b3d35;
      border-color: #79302a;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th, td {
      padding: 12px 8px;
      border-bottom: 1px solid #e5e6e0;
      text-align: left;
      font-size: 14px;
    }
    th {
      color: #5c6159;
      font-weight: 600;
    }
    .pill {
      display: inline-flex;
      align-items: center;
      min-height: 24px;
      padding: 0 9px;
      border-radius: 999px;
      background: #eef5f0;
      color: #1e5f4f;
      font-size: 13px;
    }
    .pill.off {
      background: #f7ecea;
      color: #8c332b;
    }
    @media (max-width: 720px) {
      header, .controls {
        display: grid;
        grid-template-columns: 1fr;
      }
      th:nth-child(3), td:nth-child(3) {
        display: none;
      }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>ClipMate</h1>
        <div class="muted">剪切板同步控制台</div>
      </div>
      <button class="secondary" id="refresh">刷新</button>
    </header>

    <section class="panel">
      <div class="controls">
        <label>Room
          <input id="room" placeholder="home" value="default">
        </label>
        <label>Token
          <input id="token" type="password" placeholder="CLIPMATE_TOKEN">
        </label>
        <button id="save">连接</button>
      </div>
    </section>

    <section class="panel">
      <div class="muted" id="clip">还没有连接。</div>
    </section>

    <section class="panel">
      <table>
        <thead>
          <tr>
            <th>设备</th>
            <th>状态</th>
            <th>最后在线</th>
            <th></th>
          </tr>
        </thead>
        <tbody id="devices">
          <tr><td colspan="4" class="muted">输入 token 后连接。</td></tr>
        </tbody>
      </table>
    </section>
  </main>

  <script>
    const roomInput = document.querySelector("#room");
    const tokenInput = document.querySelector("#token");
    const devicesBody = document.querySelector("#devices");
    const clipEl = document.querySelector("#clip");

    roomInput.value = localStorage.getItem("clipmate.room") || "default";
    tokenInput.value = localStorage.getItem("clipmate.token") || "";

    function authHeaders() {
      return { Authorization: `Bearer ${tokenInput.value}` };
    }

    function fmtTime(ts) {
      if (!ts) return "-";
      return new Date(ts * 1000).toLocaleString();
    }

    async function api(path, options = {}) {
      const response = await fetch(path, {
        ...options,
        headers: {
          ...authHeaders(),
          ...(options.headers || {})
        }
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      if (response.status === 204) return null;
      return response.json();
    }

    async function setDevice(device, enabled) {
      const room = encodeURIComponent(roomInput.value || "default");
      await api(`/v1/rooms/${room}/devices/${encodeURIComponent(device)}/settings`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled })
      });
      await refresh();
    }

    async function refresh() {
      const room = encodeURIComponent(roomInput.value || "default");
      try {
        const [clip, devices] = await Promise.all([
          api(`/v1/rooms/${room}/clip-meta`),
          api(`/v1/rooms/${room}/devices`)
        ]);

        if (clip) {
          clipEl.textContent = `最近同步：${clip.device}，${clip.bytes} bytes，${fmtTime(clip.updated_at)}`;
        } else {
          clipEl.textContent = "这个 room 还没有剪切板内容。";
        }

        if (!devices.length) {
          devicesBody.innerHTML = `<tr><td colspan="4" class="muted">还没有设备上线。</td></tr>`;
          return;
        }

        devicesBody.innerHTML = "";
        for (const item of devices) {
          const tr = document.createElement("tr");
          const state = item.enabled && !item.local_paused;
          const deviceTd = document.createElement("td");
          deviceTd.textContent = item.device;
          const statusTd = document.createElement("td");
          const status = document.createElement("span");
          status.className = `pill ${state ? "" : "off"}`;
          status.textContent = state ? "同步中" : (item.enabled ? "本机暂停" : "已关闭");
          statusTd.appendChild(status);
          const timeTd = document.createElement("td");
          timeTd.textContent = fmtTime(item.last_seen_at);
          const actionTd = document.createElement("td");
          const button = document.createElement("button");
          button.className = item.enabled ? "danger" : "";
          button.textContent = item.enabled ? "关闭同步" : "开启同步";
          button.addEventListener("click", () => setDevice(item.device, !item.enabled));
          actionTd.appendChild(button);
          tr.append(deviceTd, statusTd, timeTd, actionTd);
          devicesBody.appendChild(tr);
        }
      } catch (err) {
        clipEl.textContent = `连接失败：${err.message}`;
      }
    }

    document.querySelector("#save").addEventListener("click", () => {
      localStorage.setItem("clipmate.room", roomInput.value || "default");
      localStorage.setItem("clipmate.token", tokenInput.value);
      refresh();
    });
    document.querySelector("#refresh").addEventListener("click", refresh);

    if (tokenInput.value) refresh();
    setInterval(() => {
      if (tokenInput.value) refresh();
    }, 5000);
  </script>
</body>
</html>
"""


def require_auth(authorization: Optional[str]) -> None:
    if not APP_TOKEN:
        raise HTTPException(status_code=500, detail="CLIPMATE_TOKEN is not configured")

    expected = f"Bearer {APP_TOKEN}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="unauthorized")


def touch_device(room: str, device: str, local_paused: bool = False) -> DeviceState:
    room_devices = devices.setdefault(room, {})
    current = room_devices.get(device)
    state = DeviceState(
        device=device,
        enabled=current.enabled if current else True,
        local_paused=local_paused,
        last_seen_at=time.time(),
    )
    room_devices[device] = state
    return state


@app.get("/", response_class=HTMLResponse)
def index():
    return INDEX_HTML


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/v1/rooms/{room}/clip", response_model=Optional[ClipState])
def get_clip(room: str, authorization: Optional[str] = Header(default=None)):
    require_auth(authorization)
    return clips.get(room)


@app.get("/v1/rooms/{room}/clip-meta", response_model=Optional[ClipMeta])
def get_clip_meta(room: str, authorization: Optional[str] = Header(default=None)):
    require_auth(authorization)
    clip = clips.get(room)
    if not clip:
        return None
    return ClipMeta(
        device=clip.device,
        hash=clip.hash,
        updated_at=clip.updated_at,
        bytes=len(clip.text.encode("utf-8")),
    )


@app.put("/v1/rooms/{room}/clip", response_model=ClipState)
def put_clip(room: str, clip: ClipPut, authorization: Optional[str] = Header(default=None)):
    require_auth(authorization)
    device = touch_device(room, clip.device)
    if not device.enabled:
        raise HTTPException(status_code=423, detail="device sync is disabled")

    encoded_size = len(clip.text.encode("utf-8"))
    if encoded_size > MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"clipboard is larger than {MAX_BYTES} bytes")

    state = ClipState(
        text=clip.text,
        device=clip.device,
        hash=clip.hash,
        updated_at=time.time(),
    )
    clips[room] = state
    return state


@app.get("/v1/rooms/{room}/devices", response_model=list[DeviceState])
def list_devices(room: str, authorization: Optional[str] = Header(default=None)):
    require_auth(authorization)
    return sorted(
        devices.get(room, {}).values(),
        key=lambda item: item.last_seen_at,
        reverse=True,
    )


@app.post("/v1/rooms/{room}/devices/{device}/heartbeat", response_model=DeviceState)
def heartbeat(
    room: str,
    device: str,
    heartbeat: DeviceHeartbeat,
    authorization: Optional[str] = Header(default=None),
):
    require_auth(authorization)
    return touch_device(room, device, heartbeat.local_paused)


@app.put("/v1/rooms/{room}/devices/{device}/settings", response_model=DeviceState)
def update_device_settings(
    room: str,
    device: str,
    settings: DeviceSettings,
    authorization: Optional[str] = Header(default=None),
):
    require_auth(authorization)
    current = touch_device(room, device)
    state = DeviceState(
        device=device,
        enabled=settings.enabled,
        local_paused=current.local_paused,
        last_seen_at=current.last_seen_at,
    )
    devices.setdefault(room, {})[device] = state
    return state
