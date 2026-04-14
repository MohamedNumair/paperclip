#!/bin/bash

# Default values
RESET_DB=false
SKIP_HEALTH_CHECK=false

# Parse command-line arguments
for arg in "$@"
do
    case $arg in
        --reset-db)
        RESET_DB=true
        shift
        ;;
        --skip-health-check)
        SKIP_HEALTH_CHECK=true
        shift
        ;;
    esac
done

set -e

ensure_postgres_running() {
    if pg_isready -h localhost -p 5432 -q; then
        echo "[paperclip] Local PostgreSQL is already running."
        return 0
    fi

    echo "[paperclip] PostgreSQL not running, attempting to start..."
    if command -v brew &>/dev/null; then
        brew services start postgresql
    elif command -v systemctl &>/dev/null; then
        sudo systemctl start postgresql
    elif command -v service &>/dev/null; then
        sudo service postgresql start
    else
        echo "[paperclip] ERROR: Cannot start PostgreSQL automatically. Please start it manually." >&2
        exit 1
    fi

    # Wait up to 15 seconds for Postgres to become ready
    for i in $(seq 1 15); do
        if pg_isready -h localhost -p 5432 -q; then
            echo "[paperclip] PostgreSQL is now ready."
            return 0
        fi
        sleep 1
    done

    echo "[paperclip] ERROR: PostgreSQL did not become ready in time." >&2
    exit 1
}

stop_paperclip_processes() {
    echo "[paperclip] Stopping running Paperclip-related processes..."
    PORTS=(3100 13100 54329)
    for port in "${PORTS[@]}"; do
        PIDS=$(lsof -t -i:$port -sTCP:LISTEN || true)
        if [ -n "$PIDS" ]; then
            echo "Stopping processes on port $port with PIDs: $PIDS"
            kill -9 $PIDS >/dev/null 2>&1 || true
        fi
    done

    # Find and kill embedded postgres processes
    PIDS=$(ps aux | grep '[p]ostgres' | grep '@embedded-postgres' | awk '{print $2}' || true)
    if [ -n "$PIDS" ]; then
        echo "Stopping embedded-postgres processes with PIDs: $PIDS"
        kill -9 $PIDS >/dev/null 2>&1 || true
    fi
}

reset_paperclip_db_lock() {
    echo "[paperclip] Resetting stale lock state..."
    DB_DIR="$HOME/.paperclip/instances/default/db"
    PID_FILE="$DB_DIR/postmaster.pid"

    if [ -f "$PID_FILE" ]; then
        rm -f "$PID_FILE"
    fi

    if [ "$RESET_DB" = true ]; then
        if [ -d "$DB_DIR" ]; then
            echo "[paperclip] Resetting embedded database directory: $DB_DIR"
            rm -rf "$DB_DIR"
        fi
    fi
}

wait_for_health_check() {
    URL="http://127.0.0.1:3100/api/health"
    MAX_ATTEMPTS=30
    echo "[paperclip] Waiting for health check at $URL..."

    for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
        if curl -s --head --fail "$URL" > /dev/null; then
            echo "[paperclip] Health check OK: $URL"
            curl -s "$URL"
            echo ""
            return 0
        else
            sleep 1
        fi
    done

    echo "Paperclip health check failed after waiting for startup." >&2
    return 1
}

# --- Main Script ---

ensure_postgres_running
stop_paperclip_processes
reset_paperclip_db_lock

echo "[paperclip] Starting pnpm dev..."
cd "$(dirname "$0")/.."

if [ "$SKIP_HEALTH_CHECK" = false ]; then
    echo "[paperclip] Startup will continue in this terminal."
    echo "[paperclip] Check health at http://127.0.0.1:3100/api/health after the server banner appears."
    (set -a; source .env; set +a; pnpm dev)
    wait_for_health_check
else
    set -a; source .env; set +a; pnpm dev
fi
