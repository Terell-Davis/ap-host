#!/usr/bin/env bash
# =============================================================================
# Archipelago.gg — Automated Docker Deployment Script
#
# Usage:
#   1. Place your custom config files next to this script (see REQUIRED FILES).
#   2. Place your ROM file next to this script and set ROM_FILENAME below.
#   3. Run:  bash deploy.sh
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
#
# OPTIONAL CUSTOM OVERRIDES:
#   - custom-edits/        (mirrors the repo structure — files here are copied
#                           on top of the repo automatically, no script changes needed)
#                           e.g. custom-edits/WebHostLib/templates/landing.html
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
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

# ── 1. Verify required config files ─────────────────────────────────────────
REQUIRED_FILES=("config.yaml" "selflaunch.yaml" "gunicorn.conf.py" "nginx.conf" "$ROM_FILENAME")

echo "[1/6] Checking required files in: $SCRIPT_DIR"
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

# ── 2. Clone or update the Archipelago repo ──────────────────────────────────
echo ""
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "[2/6] Repo already cloned — pulling latest changes..."

    # Restore files we patch so git pull has nothing to conflict with
    git -C "$REPO_DIR" checkout -- deploy/docker-compose.yml 2>/dev/null || true
    git -C "$REPO_DIR" checkout -- WebHostLib/customserver.py 2>/dev/null || true

    git -C "$REPO_DIR" pull
    echo "  ✓ Repository updated."
else
    echo "[2/6] Cloning Archipelago repository..."
    git clone "$REPO_URL" "$REPO_DIR"
    echo "  ✓ Repository cloned."
fi

if [[ ! -d "$DEPLOY_DIR" ]]; then
    echo "ERROR: deploy/ folder not found inside cloned repo at $DEPLOY_DIR"
    exit 1
fi

# ── 3. Copy custom config files into deploy/ ────────────────────────────────
echo ""
echo "[3/6] Copying custom config files into $DEPLOY_DIR ..."

for f in config.yaml selflaunch.yaml gunicorn.conf.py nginx.conf; do
    cp "$SCRIPT_DIR/$f" "$DEPLOY_DIR/$f"
    echo "  Copied: $f → deploy/$f"
done

# Copy ROM into the Archipelago repo root
cp "$SCRIPT_DIR/$ROM_FILENAME" "$REPO_DIR/$ROM_FILENAME"
echo "  Copied: $ROM_FILENAME → $CLONE_DIR/$ROM_FILENAME"

# ── 4. Apply custom-edits overlay ───────────────────────────────────────────
# To add/replace any file in the repo, mirror its path inside custom-edits/.
# e.g. to replace WebHostLib/templates/landing.html, place your version at:
#      custom-edits/WebHostLib/templates/landing.html
# No script changes needed — just drop files in and re-run.
CUSTOM_EDITS_DIR="$SCRIPT_DIR/custom-edits"

echo ""
echo "[4/6] Applying custom-edits overlay..."

if [[ -d "$CUSTOM_EDITS_DIR" ]]; then
    cp -rv "$CUSTOM_EDITS_DIR/." "$REPO_DIR/" | sed 's/^/  Overlaid: /'
    echo "  ✓ custom-edits applied."
else
    echo "  (No custom-edits/ folder found — skipping.)"
fi

# ── 5. Patch source files ────────────────────────────────────────────────────
echo ""
echo "[5/6] Patching source files..."

# --- 5a. docker-compose.yml: port + strip example_ prefixes -----------------
COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "ERROR: docker-compose.yml not found at $COMPOSE_FILE"
    exit 1
fi

sed -i "s/['\"]8080:\([0-9]*\)['\"]/\"${HOST_PORT}:\1\"/g" "$COMPOSE_FILE"
sed -i "s/- 8080:\([0-9]*\)/- ${HOST_PORT}:\1/g"           "$COMPOSE_FILE"

if grep -q "$HOST_PORT" "$COMPOSE_FILE"; then
    echo "  ✓ docker-compose: port updated 8080 → $HOST_PORT"
else
    echo "  ⚠ WARNING: Could not verify port change — check $COMPOSE_FILE manually."
fi

sed -i "s|\./example_|\./|g" "$COMPOSE_FILE"

if ! grep -q "example_" "$COMPOSE_FILE"; then
    echo "  ✓ docker-compose: removed all 'example_' prefixes from volume mounts"
else
    echo "  ⚠ WARNING: Some 'example_' entries may remain — check $COMPOSE_FILE manually."
fi

# --- 5c. docker-compose.yml: inject ROM volume mount -----------------------
# The ROM must be explicitly mounted into the container — copying it to the
# repo root is not enough. We add it to the volumes: block of the app service.
# The container path /archipelago/<rom> matches where Archipelago expects it.
ROM_HOST_PATH="../${ROM_FILENAME}"   # relative to deploy/, points to repo root
ROM_CONTAINER_PATH="/archipelago/${ROM_FILENAME}"
ROM_VOLUME_LINE="      - ${ROM_HOST_PATH}:${ROM_CONTAINER_PATH}:ro"

if grep -qF "$ROM_CONTAINER_PATH" "$COMPOSE_FILE"; then
    echo "  ✓ docker-compose: ROM volume already present, skipping."
else
    # Insert the ROM mount after the last existing volume entry (lines starting with "      - ")
    # This uses awk to append after the final volume line in the file
    awk -v rom_line="$ROM_VOLUME_LINE" '
        /^      - / { last_vol = NR; lines[NR] = $0; next }
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last_vol) print rom_line
            }
        }
    ' "$COMPOSE_FILE" > "${COMPOSE_FILE}.tmp" && mv "${COMPOSE_FILE}.tmp" "$COMPOSE_FILE"

    if grep -qF "$ROM_CONTAINER_PATH" "$COMPOSE_FILE"; then
        echo "  ✓ docker-compose: ROM volume mount injected"
        echo "      ${ROM_HOST_PATH} → ${ROM_CONTAINER_PATH}"
    else
        echo "  ⚠ WARNING: Could not inject ROM volume — add this manually to $COMPOSE_FILE:"
        echo "      volumes:"
        echo "        $ROM_VOLUME_LINE"
    fi
fi

# --- 5b. customserver.py: patch get_random_port() range to 50000–50002 ------
CUSTOMSERVER="$REPO_DIR/WebHostLib/customserver.py"

if [[ ! -f "$CUSTOMSERVER" ]]; then
    echo "  ⚠ WARNING: WebHostLib/customserver.py not found — skipping port range patch."
else
    # Targets the exact line inside get_random_port():
    #   return random.randint(49152, 65535)
    sed -i 's/\(def get_random_port.*\)/\1/;/def get_random_port/,/^def /{s/random\.randint(49152, 65535)/random.randint(50000, 50002)/g}' "$CUSTOMSERVER"

    if grep -q "50000, 50002" "$CUSTOMSERVER"; then
        echo "  ✓ customserver.py: get_random_port() range set to 50000–50002"
    else
        echo "  ⚠ WARNING: Could not verify customserver.py patch — check $CUSTOMSERVER manually."
    fi
fi

# ── 6. Build and start Docker containers ─────────────────────────────────────
echo ""
echo "[6/6] Starting Docker containers..."
cd "$DEPLOY_DIR"

if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo "  Using: $COMPOSE_CMD"
echo ""

$COMPOSE_CMD up -d --build

# Read host from config.yaml for the completion message
CONFIG_HOST="$(grep -E '^\s*host\s*:' "$SCRIPT_DIR/config.yaml" | sed 's/.*:\s*//' | tr -d '"'"'"' ' | head -1)"
DISPLAY_HOST="${CONFIG_HOST:-localhost}"

echo ""
echo "============================================"
echo "  ✅  Deployment complete!"
echo "============================================"
echo ""
echo "  Web interface:  http://${DISPLAY_HOST}:$HOST_PORT"
echo "  Deploy folder:  $DEPLOY_DIR"
echo ""
echo "  Useful commands (run from $DEPLOY_DIR):"
echo "    View logs:    $COMPOSE_CMD logs -f"
echo "    Stop:         $COMPOSE_CMD down"
echo "    Restart:      $COMPOSE_CMD restart"
echo ""