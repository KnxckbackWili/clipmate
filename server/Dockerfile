FROM caddy:2 AS caddy

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY app.py .
COPY Caddyfile .
COPY start.sh .
RUN chmod +x start.sh

ENV CLIPMATE_MAX_BYTES=524288
ENV CLIPMATE_HTTPS_PORT=9673
ENV CLIPMATE_HTTP_PORT=80
ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data
EXPOSE 80 8080 9673

CMD ["./start.sh"]
