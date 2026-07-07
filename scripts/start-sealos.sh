#!/usr/bin/env bash
set -Eeuo pipefail

# Sealos 只创建一个应用时，所有可持久化数据都放到 /data。
export ENVIRONMENT="${ENVIRONMENT:-production}"
export HOST="${HOST:-0.0.0.0}"
export MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
export MYSQL_PORT="${MYSQL_PORT:-3306}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-xianyu_root_2026}"
export MYSQL_DATABASE="${MYSQL_DATABASE:-xianyu_data}"
export MYSQL_USER="${MYSQL_USER:-xianyu}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-xianyu_2026}"
export REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
export REDIS_PORT="${REDIS_PORT:-6379}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-xianyu_redis_2026}"
export REDIS_DB="${REDIS_DB:-0}"
export BACKEND_WEB_PORT="${BACKEND_WEB_PORT:-8089}"
export WEBSOCKET_PORT="${WEBSOCKET_PORT:-8090}"
export SCHEDULER_PORT="${SCHEDULER_PORT:-8091}"
export BACKEND_WEB_SERVICE_URL="${BACKEND_WEB_SERVICE_URL:-http://127.0.0.1:8089}"
export WEBSOCKET_SERVICE_URL="${WEBSOCKET_SERVICE_URL:-http://127.0.0.1:8090}"
export SCHEDULER_SERVICE_URL="${SCHEDULER_SERVICE_URL:-http://127.0.0.1:8091}"
export STATIC_DIR="${STATIC_DIR:-/data/static}"
export BACKUP_DIR="${BACKUP_DIR:-/data/backups}"
export BROWSER_HEADLESS="${BROWSER_HEADLESS:-true}"
export AUTO_START_CRAWL_JOBS="${AUTO_START_CRAWL_JOBS:-true}"
export AUTO_START_WEBSOCKET="${AUTO_START_WEBSOCKET:-true}"
export CORS_ORIGINS="${CORS_ORIGINS:-*}"
export JWT_ALGORITHM="${JWT_ALGORITHM:-HS256}"
export ACCESS_TOKEN_EXPIRE_MINUTES="${ACCESS_TOKEN_EXPIRE_MINUTES:-1440}"
export REFRESH_TOKEN_EXPIRE_MINUTES="${REFRESH_TOKEN_EXPIRE_MINUTES:-10080}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export SQL_ECHO="${SQL_ECHO:-false}"
export TZ="${TZ:-Asia/Shanghai}"
export STARTUP_TIMEOUT_SECONDS="${STARTUP_TIMEOUT_SECONDS:-300}"

MYSQL_DATA_DIR=/data/mysql
MYSQL_SOCKET=/run/mysqld/mysqld.sock
REDIS_DATA_DIR=/data/redis
PIDS=()

require_mysql_identifier() {
    local name="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[A-Za-z0-9_]+$ ]]; then
        echo "$name 只能包含字母、数字和下划线: $value" >&2
        exit 1
    fi
}

sql_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\\\'}"
    printf "%s" "$value"
}

cleanup() {
    local code=$?
    trap - EXIT INT TERM
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    exit "$code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

prepare_dirs() {
    require_mysql_identifier MYSQL_DATABASE "$MYSQL_DATABASE"
    require_mysql_identifier MYSQL_USER "$MYSQL_USER"

    mkdir -p \
        "$MYSQL_DATA_DIR" \
        "$REDIS_DATA_DIR" \
        "$STATIC_DIR/uploads" \
        "$BACKUP_DIR" \
        /data/browser_data \
        /data/logs/backend-web \
        /data/logs/websocket \
        /data/logs/scheduler \
        /run/mysqld

    chown -R mysql:mysql "$MYSQL_DATA_DIR" /run/mysqld
    chown -R redis:redis "$REDIS_DATA_DIR"

    rm -rf /app/backend-web/logs /app/websocket/logs /app/scheduler/logs /app/websocket/browser_data
    ln -s /data/logs/backend-web /app/backend-web/logs
    ln -s /data/logs/websocket /app/websocket/logs
    ln -s /data/logs/scheduler /app/scheduler/logs
    ln -s /data/browser_data /app/websocket/browser_data
}

wait_mysql() {
    echo "等待 MariaDB 启动，最长 ${STARTUP_TIMEOUT_SECONDS}s"
    for _ in $(seq 1 "$STARTUP_TIMEOUT_SECONDS"); do
        if mysqladmin --protocol=socket --socket="$MYSQL_SOCKET" ping --silent >/dev/null 2>&1 \
            || mysqladmin --protocol=socket --socket="$MYSQL_SOCKET" -uroot -p"$MYSQL_ROOT_PASSWORD" ping --silent >/dev/null 2>&1; then
            echo "MariaDB 已就绪"
            return 0
        fi
        sleep 1
    done
    echo "MariaDB 启动超时" >&2
    exit 1
}

mysql_root_sql() {
    local sql_file
    sql_file="$(mktemp)"
    cat > "$sql_file"
    mysql --protocol=socket --socket="$MYSQL_SOCKET" -uroot < "$sql_file" 2>/dev/null \
        || mysql --protocol=socket --socket="$MYSQL_SOCKET" -uroot -p"$MYSQL_ROOT_PASSWORD" < "$sql_file"
    rm -f "$sql_file"
}

start_mysql() {
    if [ ! -d "$MYSQL_DATA_DIR/mysql" ]; then
        mariadb-install-db \
            --user=mysql \
            --datadir="$MYSQL_DATA_DIR" \
            --auth-root-authentication-method=normal \
            >/dev/null
    fi

    mariadbd \
        --user=mysql \
        --datadir="$MYSQL_DATA_DIR" \
        --socket="$MYSQL_SOCKET" \
        --bind-address=127.0.0.1 \
        --port=3306 \
        --character-set-server=utf8mb4 \
        --collation-server=utf8mb4_unicode_ci \
        --max-connections=300 \
        --max-allowed-packet=256M \
        --default-time-zone="+08:00" &
    PIDS+=("$!")

    wait_mysql

    local mysql_root_password_sql mysql_password_sql
    mysql_root_password_sql="$(sql_escape "$MYSQL_ROOT_PASSWORD")"
    mysql_password_sql="$(sql_escape "$MYSQL_PASSWORD")"

    mysql_root_sql <<SQL
CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$MYSQL_USER'@'%' IDENTIFIED BY '$mysql_password_sql';
CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$mysql_password_sql';
ALTER USER '$MYSQL_USER'@'%' IDENTIFIED BY '$mysql_password_sql';
ALTER USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$mysql_password_sql';
GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%';
GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'localhost';
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password_sql';
FLUSH PRIVILEGES;
SQL
}

wait_redis() {
    echo "等待 Redis 启动，最长 ${STARTUP_TIMEOUT_SECONDS}s"
    for _ in $(seq 1 "$STARTUP_TIMEOUT_SECONDS"); do
        if redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" ping >/dev/null 2>&1; then
            echo "Redis 已就绪"
            return 0
        fi
        sleep 1
    done
    echo "Redis 启动超时" >&2
    exit 1
}

start_redis() {
    runuser -u redis -- redis-server \
        --bind 127.0.0.1 \
        --port 6379 \
        --requirepass "$REDIS_PASSWORD" \
        --dir "$REDIS_DATA_DIR" \
        --appendonly yes \
        --maxmemory 256mb \
        --maxmemory-policy allkeys-lru &
    PIDS+=("$!")
    wait_redis
}

wait_http() {
    local name="$1"
    local url="$2"
    echo "等待 $name 启动: $url，最长 ${STARTUP_TIMEOUT_SECONDS}s"
    for _ in $(seq 1 "$STARTUP_TIMEOUT_SECONDS"); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            echo "$name 已就绪"
            return 0
        fi
        sleep 1
    done
    echo "$name 启动超时: $url" >&2
    exit 1
}

start_python_service() {
    local name="$1"
    local dir="$2"
    local port="$3"
    (
        cd "$dir"
        exec python main.py
    ) &
    PIDS+=("$!")
    wait_http "$name" "http://127.0.0.1:$port/health"
}

prepare_dirs
start_mysql
start_redis
start_python_service backend-web /app/backend-web "$BACKEND_WEB_PORT"
start_python_service websocket /app/websocket "$WEBSOCKET_PORT"
start_python_service scheduler /app/scheduler "$SCHEDULER_PORT"

nginx -g "daemon off;" &
PIDS+=("$!")
wait_http nginx http://127.0.0.1/health

echo "xianyu-auto-reply Sealos 单应用已启动"
wait -n "${PIDS[@]}"
