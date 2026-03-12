#!/usr/bin/env bash

REPO_DIR="archipelago"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/$REPO_DIR/deploy"

COMPOSE_CMD="docker compose"
cd "$DEPLOY_DIR"

usage() {
    echo ""
    echo "Usage: bash ap-cmd.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start    Start containers (no rebuild)"
    echo "  stop     Stop containers"
    echo "  restart  Restart containers (no rebuild)"
    echo "  status   Show running container status"
    echo "  logs     Tail live logs (Ctrl+C to exit)"
    echo ""
}

cmd_start() {
    echo "Starting Archipelago containers..."
    $COMPOSE_CMD up -d
    echo ""
    echo "✓ Containers started."
}

cmd_stop() {
    echo "Stopping Archipelago containers..."
    $COMPOSE_CMD down
    echo ""
    echo "Containers stopped."
}

cmd_restart() {
    echo "Restarting Archipelago containers..."
    $COMPOSE_CMD restart
    echo ""
    echo "Containers restarted."
}

cmd_status() {
    echo "Container status:"
    echo ""
    $COMPOSE_CMD ps
}

cmd_logs() {
    echo "Tailing logs (Ctrl+C to exit)..."
    echo ""
    $COMPOSE_CMD logs -f
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
    start)   cmd_start   ;;
    stop)    cmd_stop    ;;
    restart) cmd_restart ;;
    status)  cmd_status  ;;
    logs)    cmd_logs    ;;
    *)
        echo "ERROR: Unknown or missing command: '${1:-}'"
        usage
        exit 1
        ;;
esac