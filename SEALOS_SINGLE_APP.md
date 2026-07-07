# Sealos 单应用部署

这个目录里的 `Dockerfile.sealos` 会把前端、backend-web、websocket、scheduler、MariaDB、Redis 打进同一个镜像。Sealos 里只需要创建一个应用，不需要再手动创建数据库或 Redis。

## 构建并推送镜像

```bash
docker build -f Dockerfile.sealos -t registry.example.com/xianyu-auto-reply-sealos:latest .
docker push registry.example.com/xianyu-auto-reply-sealos:latest
```

把镜像名换成你自己的镜像仓库地址。

如果 Docker Hub 拉取超时，用国内镜像源构建：

```bash
docker build -f Dockerfile.sealos \
  --build-arg NODE_IMAGE=m.daocloud.io/docker.io/library/node:18-bookworm-slim \
  --build-arg PYTHON_IMAGE=m.daocloud.io/docker.io/library/python:3.11-slim-bookworm \
  -t registry.example.com/xianyu-auto-reply-sealos:latest .
```

## Sealos 应用配置

- 镜像：`registry.example.com/xianyu-auto-reply-sealos:latest`
- 实例数：`1`
- 对外端口：`80`
- 存储挂载：`/data`
- 存储大小：建议 `20Gi` 起
- 资源：建议 `2C / 4G` 起，账号多或采集任务多用 `4C / 8G`

环境变量建议至少改这几个：

```env
MYSQL_ROOT_PASSWORD=换成强密码
MYSQL_PASSWORD=换成强密码
REDIS_PASSWORD=换成强密码
SQL_ECHO=false
TZ=Asia/Shanghai
```

可选环境变量：

```env
MYSQL_DATABASE=xianyu_data
MYSQL_USER=xianyu
REDIS_DB=0
CORS_ORIGINS=*
AUTO_START_CRAWL_JOBS=true
AUTO_START_WEBSOCKET=true
BROWSER_HEADLESS=true
LOG_LEVEL=INFO
STARTUP_TIMEOUT_SECONDS=300
```

## 注意

- 只能跑单实例，不要在 Sealos 里扩容副本数；数据库和 Redis 都在这个容器里。
- `/data` 必须挂持久化存储，否则重启或重建应用会丢数据库、Redis、上传文件、备份和浏览器登录态。
- `MYSQL_ROOT_PASSWORD` 首次启动后不要随便改；如果改了，旧数据目录里的 root 密码不会自动同步。
- 这个镜像内置的是 MariaDB，作为 MySQL 兼容服务使用；要严格 MySQL 8 或高可用，再拆成独立数据库。
