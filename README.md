# ClipMate

一个给 Mac / Windows 用的轻量剪切板同步方案：Unraid 上部署 Docker 中转服务，每台电脑各运行一个后台客户端。当前版本同步文本剪切板，不同步图片和文件。

## 推荐拓扑

```text
Mac / Windows  <----HTTPS---->  Unraid / 公网 IP / 反代  <----HTTPS---->  Mac / Windows
```

最方便、也最稳的做法：

1. Unraid 跑本项目的 `clipmate-relay` Docker。
2. 用 Nginx Proxy Manager、Caddy 或 Cloudflare Tunnel 给它套 HTTPS。
3. Mac 安装 `mac-client` 的 LaunchAgent，Windows 安装 `windows-client` 的计划任务，开机自动同步。

如果两台机器都在你自己的网络里，或者你愿意装 Tailscale，也可以不暴露公网端口，直接用 Tailscale 内网地址访问 Unraid。

## Unraid 部署

### 最省事：一个模板 URL 安装

可以做到你说的那种“一个网址就好”。但这个网址必须指向一个公网 Unraid 模板 XML，而且 Docker 镜像也必须已经发布到公网镜像仓库。

这个项目已经准备好了发布流程：

1. 把项目推到 GitHub。
2. GitHub Actions 会发布镜像到 GHCR：

```text
ghcr.io/knxckbackwili/clipmate-relay:latest
```

3. 替换 Unraid 模板里的 GitHub 用户名：

```bash
./unraid/patch-template-owner.sh KnxckbackWili
```

4. 在 Unraid 里添加模板 URL：

```text
https://github.com/KnxckbackWili/clipmate
```

如果你的 Unraid 版本要填单个 XML 文件 URL，用这个：

```text
https://raw.githubusercontent.com/KnxckbackWili/clipmate/main/clipmate-relay.xml
```

之后安装时只需要填 `Token`，外部端口默认 `9673`。更详细说明在 [unraid/README.md](/Users/knxckbackwili/Documents/New%20project/unraid/README.md)。

### 一条命令部署

把整个项目文件夹复制到 Unraid，例如：

```text
/mnt/user/appdata/clipmate
```

然后在 Unraid 终端运行：

```bash
cd /mnt/user/appdata/clipmate
chmod +x unraid/install.sh
./unraid/install.sh
```

脚本会自动生成 `.env` 里的 token，构建 Docker 镜像，并启动服务。启动后打开：

```text
http://你的-unraid-ip:9673/
```

这个页面就是 ClipMate 的 Web 图形界面，可以查看设备状态、最近同步信息，并对每台设备开关同步。

### 手动部署

先生成一个长 token：

```bash
openssl rand -hex 32
```

在项目根目录创建 `.env`：

```bash
CLIPMATE_TOKEN=把上一步生成的长token放这里
```

启动：

```bash
docker compose up -d --build
```

健康检查：

```bash
curl http://你的-unraid-ip:9673/health
```

Web 图形界面：

```text
http://你的-unraid-ip:9673/
```

公网使用时，建议把 `9673` 放在反代后面，例如：

```text
https://clip.example.com -> http://unraid-ip:9673
```

不要直接裸奔 HTTP 暴露到公网。剪切板通常有密码、验证码、私密文本，HTTPS 很重要。

### Unraid 模板

我也放了一个 Unraid Docker 模板：

```text
unraid/clipmate-relay.xml
```

注意：模板里的 `Repository` 需要替换成你发布后的 Docker 镜像地址，例如 Docker Hub 或 GHCR。只要镜像发布出来，这个 XML 就可以导入 Unraid 的模板系统，变成更接近“一键安装”的体验。

## Mac 安装

### 原生菜单栏 App

构建：

```bash
cd "/Users/knxckbackwili/Documents/New project"
./macos-app/ClipMateMenuBar/build.sh
open "./macos-app/ClipMateMenuBar/build/ClipMate.app"
```

启动后菜单栏会出现 `ClipMate`。在 `Settings...` 里填：

```text
Server: http://你的-unraid-ip:9673
Token: 你的长token
Room: home
Encryption Secret: 你自己的共享加密密钥
```

`Encryption Secret` 为空时是不加密同步；不为空时启用端到端加密。所有设备必须填同一个密钥。

### 脚本后台版

在两台 Mac 上分别运行：

```bash
cd "/Users/knxckbackwili/Documents/New project/mac-client"
chmod +x install_launch_agent.sh uninstall_launch_agent.sh clipmate.py
./install_launch_agent.sh "https://clip.example.com" "你的长token" "home"
```

如果你还没配 HTTPS，只在内网测试，可以临时用：

```bash
./install_launch_agent.sh "http://unraid-ip:9673" "你的长token" "home" "你的共享加密密钥"
```

脚本后台版启用加密前需要安装依赖：

```bash
python3 -m pip install -r requirements.txt
```

查看日志：

```bash
tail -f /tmp/clipmate.out.log /tmp/clipmate.err.log
```

暂停、恢复和查看状态：

```bash
./pause.sh
./resume.sh
./status.sh
```

卸载：

```bash
./uninstall_launch_agent.sh
```

## Windows 安装

### 托盘 GUI

Windows 托盘版需要 PowerShell 7，因为加密同步使用系统 `.NET` 的 AES-GCM。

在 PowerShell 7 里运行：

```powershell
cd windows-client\gui
.\clipmate-tray.ps1
```

右下角托盘会出现 ClipMate，右键可以暂停/恢复、打开设置、退出。设置里填：

```text
Server: http://你的-unraid-ip:9673
Token: 你的长token
Room: home
Encryption Secret: 你自己的共享加密密钥
```

开机启动：

```powershell
.\install_startup.ps1
```

取消开机启动：

```powershell
.\uninstall_startup.ps1
```

### 脚本后台版

在 Windows PowerShell 中进入 `windows-client` 目录，然后运行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\install_scheduled_task.ps1 -Server "https://clip.example.com" -Token "你的长token" -Room "home"
```

如果还没配 HTTPS，只在内网测试，可以临时用：

```powershell
.\install_scheduled_task.ps1 -Server "http://unraid-ip:9673" -Token "你的长token" -Room "home" -Secret "你的共享加密密钥"
```

查看任务：

```powershell
Get-ScheduledTask -TaskName ClipMate
```

查看日志：

```powershell
Get-Content "$env:LOCALAPPDATA\ClipMate\clipmate.log" -Wait
```

暂停、恢复和查看状态：

```powershell
.\pause.ps1
.\resume.ps1
.\status.ps1
```

卸载：

```powershell
.\uninstall_scheduled_task.ps1
```

## 使用方式

所有电脑使用同一个 `server-url`、`token` 和 `room`。任意一台复制文本，其他电脑通常在 1 秒内收到。

打开服务端 Web 界面后，输入 room 和 token，就能看到上线设备。每台设备右侧都有开关；关闭某台设备后，它会保持在线，但不会上传或拉取剪切板。

可以用不同 room 隔离不同设备组，例如：

```bash
./install_launch_agent.sh "https://clip.example.com" "你的长token" "work"
```

## 安全说明

- 服务端只在内存里保存每个 room 的最后一条文本，容器重启后清空。
- 服务端不主动落盘剪切板内容。
- 当前版本依赖 HTTPS 保护传输内容，token 负责访问控制。
- 设置 `Encryption Secret` / `CLIPMATE_SECRET` 后启用端到端加密，服务器只能看到密文、设备名、room、时间和大小。
- 端到端加密协议见 [docs/encryption.md](/Users/knxckbackwili/Documents/New%20project/docs/encryption.md)。

## 下一步可升级

- 支持图片剪切板。
- 增加剪切板历史，但需要更认真处理隐私和清理策略。
