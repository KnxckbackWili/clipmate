# Unraid One URL Install

Unraid 真正“一键安装”的前提是：服务端镜像已经发布到公网镜像仓库，例如 GHCR 或 Docker Hub，并且模板 XML 也能通过公网 URL 访问。

这个项目已经带了 GitHub Actions。推到 GitHub 后，它会自动发布镜像：

```text
ghcr.io/knxckbackwili/clipmate-relay:latest
```

之后 Unraid 里优先添加这个模板仓库 URL：

```text
https://github.com/KnxckbackWili/clipmate
```

如果你的 Unraid 页面要求填单个 XML 文件 URL，用这个：

```text
https://raw.githubusercontent.com/KnxckbackWili/clipmate/main/clipmate-relay.xml
```

安装时只填两个东西：

- `Web UI Port`: 默认 `9673`
- `Token`: 随机长密码，可以用 `openssl rand -hex 32` 生成

安装后打开：

```text
http://你的-unraid-ip:9673/
```

如果你想更进一步变成 Community Applications 里能搜到的应用，需要把模板提交到 Unraid 社区模板仓库；自用的话，raw XML URL 已经够用了。
