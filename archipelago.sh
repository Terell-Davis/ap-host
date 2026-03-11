#!/usr/bin/env bash
# =============================================================================
# Archipelago.gg — Container Management Script
# Usage:  bash archipelago.sh [start|stop|restart|status|logs]
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
# CONFIGURE TO MATCH install-archipelago.sh
# --------------------------------------------------------------------------
CLONE_DIR="archipelago"
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/$CLONE_DIR/deploy"

# Resolve compose command once
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

# Verify deploy dir exists
if [[ ! -d "$DEPLOY_DIR" ]]; then
    echo "ERROR: Deploy directory not found at $DEPLOY_DIR"
    echo "       Run install-archipelago.sh first."
    exit 1
fi

cd "$DEPLOY_DIR"

# ── Helper: print usage ──────────────────────────────────────────────────────
usage() {
    echo ""
    echo "Usage: bash archipelago.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start    Start containers (no rebuild)"
    echo "  stop     Stop containers"
    echo "  restart  Restart containers (no rebuild)"
    echo "  status   Show running container status"
    echo "  logs     Tail live logs (Ctrl+C to exit)"
    echo ""
}

# ── Commands ─────────────────────────────────────────────────────────────────
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
    echo "✓ Containers stopped."
}

cmd_restart() {
    echo "Restarting Archipelago containers..."
    $COMPOSE_CMD restart
    echo ""
    echo "✓ Containers restarted."
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