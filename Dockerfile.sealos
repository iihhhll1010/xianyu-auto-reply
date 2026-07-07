# Sealos 单应用镜像：前端、后端、WebSocket、Scheduler、MariaDB、Redis 放在同一个容器内。
ARG NODE_IMAGE=node:18-bookworm-slim
ARG PYTHON_IMAGE=python:3.11-slim-bookworm

FROM ${NODE_IMAGE} AS frontend-builder

RUN npm config set registry https://registry.npmmirror.com

WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

FROM ${PYTHON_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    TZ=Asia/Shanghai

RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    gcc \
    mariadb-client \
    mariadb-server \
    nginx \
    procps \
    redis-server \
    tini \
    util-linux \
    fonts-dejavu-core \
    fonts-liberation \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY common /app/common
COPY backend-web /app/backend-web
COPY websocket /app/websocket
COPY scheduler /app/scheduler
COPY launcher /app/launcher

RUN python -c "import tomllib; deps=[]; paths=('/app/backend-web/pyproject.toml','/app/websocket/pyproject.toml','/app/scheduler/pyproject.toml'); [deps.extend(tomllib.load(open(p,'rb')).get('project',{}).get('dependencies',[])) for p in paths]; open('/tmp/requirements.txt','w',encoding='utf-8').write('\n'.join(dict.fromkeys(deps)))" \
    && pip install --no-cache-dir -r /tmp/requirements.txt \
    && python -m playwright install --with-deps chromium \
    && rm -f /tmp/requirements.txt

COPY docker/sealos/nginx.conf /etc/nginx/conf.d/default.conf
COPY scripts/start-sealos.sh /usr/local/bin/start-sealos
COPY --from=frontend-builder /build/frontend/dist /usr/share/nginx/html

RUN chmod +x /usr/local/bin/start-sealos \
    && mkdir -p /data/mysql /data/redis /data/static /data/backups /data/browser_data /data/logs \
    && rm -f /etc/nginx/sites-enabled/default

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
    CMD curl -fsS http://127.0.0.1/health >/dev/null || exit 1

CMD ["/usr/bin/tini", "--", "/usr/local/bin/start-sealos"]
