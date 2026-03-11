#!/usr/bin/env bash
# =============================================================================
# Archipelago.gg — Automated Docker Deployment Script
#
# Usage:
#   1. Place your custom config files next to this script (see REQUIRED FILES).
#   2. Place your ROM file next to this script and set ROM_FILENAME below.
#   3. Run
#
# On subsequent runs the script will pull the latest repo changes and
# re-apply all custom config(s).
#
# REQUIRED FILES (must exist alongside this script before running):
#   - config.yaml          (Archipelago host config)
#   - selflaunch.yaml      (self-launch game config)
#   - gunicorn.conf.py     (gunicorn worker/bind settings)
#   - nginx.conf           (nginx reverse-proxy config)
#   - {rom}     (Probably named: Zelda no Densetsu - Kamigami no Triforce (Japan).sfc)
# =============================================================================

set -euo pipefail

# CONFIGURE BEFORE RUNNING
# --------------------------------------------------------------------------
ROM_FILENAME="Zelda no Densetsu - Kamigami no Triforce (Japan).sfc"
REPO_URL="https://github.com/ArchipelagoMW/Archipelago.git"
CLONE_DIR="archipelago"
HOST_PORT="8181"     # external port 
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/$CLONE_DIR"
DEPLOY_DIR="$REPO_DIR/deploy"

echo "============================================"
echo "  Archipelago.gg — Automated Docker Deploy"
echo "============================================"
echo ""

# Verify config files
REQUIRED_FILES=("config.yaml" "selflaunch.yaml" "gunicorn.conf.py" "nginx.conf" "$ROM_FILENAME")

echo "[1/5] Checking required files in: $SCRIPT_DIR"
MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
        echo "  ✗ MISSING: $f"
        MISSING=1
    else
        echo "  ✓ Found:   $f"
    fi
done

if [[ $MISSING -eq 1 ]]; then
    echo ""
    echo "ERROR: One or more required files are missing."
    echo "Place all required files next to deploy.sh and try again."
    exit 1
fi

# Clone/update the Archipelago repo 
echo ""
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "[2/5] Repo already cloned — pulling latest changes..."

    # Restore docker-compose.yml to its original tracked state before pulling
    # so git doesn't complain about modifications from a previous run.
    git -C "$REPO_DIR" checkout -- deploy/docker-compose.yml 2>/dev/null || true

    git -C "$REPO_DIR" pull
    echo "  ✓ Repository updated."
else
    echo "[2/5] Cloning Archipelago repository..."
    git clone "$REPO_URL" "$REPO_DIR"
    echo "  ✓ Repository cloned."
fi

if [[ ! -d "$DEPLOY_DIR" ]]; then
    echo "ERROR: deploy/ folder not found inside cloned repo at $DEPLOY_DIR"
    exit 1
fi

# Copy custom config files into deploy/
echo ""
echo "[3/5] Copying custom config files into $DEPLOY_DIR ..."

for f in config.yaml selflaunch.yaml gunicorn.conf.py nginx.conf; do
    cp "$SCRIPT_DIR/$f" "$DEPLOY_DIR/$f"
    echo "  Copied: $f → deploy/$f"
done

# Copy ROM into the Archipelago repo root
cp "$SCRIPT_DIR/$ROM_FILENAME" "$REPO_DIR/$ROM_FILENAME"
echo "  Copied: $ROM_FILENAME → $CLONE_DIR/$ROM_FILENAME"

# Patch docker-compose.yml
#    a) Change host port 8080 → 8181
#    b) Strip "example_" prefix from all volume mount filenames
COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"

echo ""
echo "[4/5] Patching docker-compose.yml..."

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "ERROR: docker-compose.yml not found at $COMPOSE_FILE"
    exit 1
fi

sed -i "s/['\"]8080:\([0-9]*\)['\"]/\"${HOST_PORT}:\1\"/g" "$COMPOSE_FILE"
sed -i "s/- 8080:\([0-9]*\)/- ${HOST_PORT}:\1/g"           "$COMPOSE_FILE"

if grep -q "$HOST_PORT" "$COMPOSE_FILE"; then
    echo "  ✓ Port updated: 8080 → $HOST_PORT"
else
    echo "  ⚠ WARNING: Could not verify port change — check $COMPOSE_FILE manually."
fi

sed -i "s|\./example_|\./|g" "$COMPOSE_FILE"

if ! grep -q "example_" "$COMPOSE_FILE"; then
    echo "  ✓ Removed all 'example_' prefixes from volume mounts"
else
    echo "  ⚠ WARNING: Some 'example_' entries may remain — check $COMPOSE_FILE manually."
fi

# Build and start Docker containers
echo ""
echo "[5/5] Starting Docker containers..."
cd "$DEPLOY_DIR"

if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else─────────────────────────────────────
    COMPOSE_CMD="docker-compose"
fi

echo "  Using: $COMPOSE_CMD"
echo ""

$COMPOSE_CMD up -d --build

echo ""
echo "============================================"
echo "  ✅  Deployment complete!"
echo "============================================"
echo ""
echo "  Web interface:  http://localhost:$HOST_PORT"
echo "  Deploy folder:  $DEPLOY_DIR"
echo ""
echo "  Useful commands (run from $DEPLOY_DIR):"
echo "    View logs:    $COMPOSE_CMD logs -f"
echo "    Stop:         $COMPOSE_CMD down"
echo "    Restart:      $COMPOSE_CMD restart"
echo ""