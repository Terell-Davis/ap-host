#!/usr/bin/env bash

ROM_FILENAME="Zelda no Densetsu - Kamigami no Triforce (Japan).sfc"
REPO_URL="https://github.com/ArchipelagoMW/Archipelago.git"
CLONE_DIR="archipelago"
HOST_PORT="8181"     # docker external port

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/$CLONE_DIR"
DEPLOY_DIR="$REPO_DIR/deploy"

echo " Docker Deploy"

REQUIRED_FILES=("config.yaml" "selflaunch.yaml" "gunicorn.conf.py" "nginx.conf" "$ROM_FILENAME")

echo "Checking required files in: $SCRIPT_DIR"
MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
        echo " Missing: $f"
        MISSING=1
    else
        echo " Found: $f"
    fi
done

if [[ $MISSING -eq 1 ]]; then
    echo "Failed: One or more required files are missing."
    exit 1
fi

# Clone https://github.com/ArchipelagoMW/Archipelago
echo ""
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "Repo already cloned, checking git pull"

    # Restore files we patch so git pull has nothing to conflict with
    git -C "$REPO_DIR" checkout -- deploy/docker-compose.yml 2>/dev/null || true
    git -C "$REPO_DIR" checkout -- WebHostLib/customserver.py 2>/dev/null || true

    git -C "$REPO_DIR" pull
    echo "Repository updated."
else
    echo "Cloning archipelago repo"
    git clone "$REPO_URL" "$REPO_DIR"
    echo "Done"
fi


# custom configs
echo ""
echo "Copying custom config files into $DEPLOY_DIR"

for f in config.yaml selflaunch.yaml gunicorn.conf.py nginx.conf; do
    cp "$SCRIPT_DIR/$f" "$DEPLOY_DIR/$f"
done

# Copy ROM into the Archipelago repo root
cp "$SCRIPT_DIR/$ROM_FILENAME" "$REPO_DIR/$ROM_FILENAME"


CUSTOM_EDITS_DIR="$SCRIPT_DIR/custom-edits"

echo ""
echo "Overwriting webpages w/ custom-edits"

if [[ -d "$CUSTOM_EDITS_DIR" ]]; then
    cp -rv "$CUSTOM_EDITS_DIR/." "$REPO_DIR/" | sed 's/^/  Overlaid: /'
    echo "Custom edits applied"
else
    echo "None found."
fi

# Modify repo files - Okay I will admit I did use claude for this cause wow I suck at regex
#-------------------------------------------------------------------------------------------
COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"

# Port Change
sed -i "s/['\"]8080:\([0-9]*\)['\"]/\"${HOST_PORT}:\1\"/g" "$COMPOSE_FILE"
sed -i "s/- 8080:\([0-9]*\)/- ${HOST_PORT}:\1/g"           "$COMPOSE_FILE"

if grep -q "$HOST_PORT" "$COMPOSE_FILE"; then
    echo "docker-compose: port updated 8080 → $HOST_PORT"
fi

# Removing example_ for the config file on the host
sed -i "s|\./example_|\./|g" "$COMPOSE_FILE"

if ! grep -q "example_" "$COMPOSE_FILE"; then
    echo "docker-compose: removed all 'example_' prefixes from volume mounts"
fi

# Passing through the rom because it didn't get copied when the volume was made
ROM_HOST_PATH="../${ROM_FILENAME}"
ROM_CONTAINER_PATH="/app/${ROM_FILENAME}"
ROM_VOLUME_LINE="      - ${ROM_HOST_PATH}:${ROM_CONTAINER_PATH}"

if grep -qF "$ROM_CONTAINER_PATH" "$COMPOSE_FILE"; then
    echo "docker-compose: ROM volume already present, skipping."
else
    # Insert the ROM mount into the multiworld service volumes block,
    # after the last existing volume entry under that service specifically.
    # We track when we're inside the multiworld: service and find its
    # volumes: block, then append after the last "      - " line in it.
    awk -v rom_line="$ROM_VOLUME_LINE" '
        /^  multiworld:/ { in_multiworld = 1 }
        /^  [a-z]/ && !/^  multiworld:/ { in_multiworld = 0 }
        in_multiworld && /^    volumes:/ { in_volumes = 1 }
        in_multiworld && in_volumes && /^      - / { last_vol = NR }
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last_vol) print rom_line
            }
        }
    ' "$COMPOSE_FILE" > "${COMPOSE_FILE}.tmp" && mv "${COMPOSE_FILE}.tmp" "$COMPOSE_FILE"

    if grep -qF "$ROM_CONTAINER_PATH" "$COMPOSE_FILE"; then
        echo "docker-compose: ROM volume mount injected into multiworld service"
        echo "      ${ROM_HOST_PATH} → ${ROM_CONTAINER_PATH}"
    else
        echo "Failed: Could not inject ROM volume — add this manually under multiworld.volumes in $COMPOSE_FILE:"
        echo "        $ROM_VOLUME_LINE"
    fi
fi

# Change customserver.py get_random_prot function to limit which ports are allowed to be open
CUSTOMSERVER="$REPO_DIR/WebHostLib/customserver.py"

if [[ ! -f "$CUSTOMSERVER" ]]; then
    echo " WARNING: WebHostLib/customserver.py not found — skipping port range patch."
else
    # Targets the exact line inside get_random_port():
    #   return random.randint(49152, 65535)
    sed -i 's/\(def get_random_port.*\)/\1/;/def get_random_port/,/^def /{s/random\.randint(49152, 65535)/random.randint(50000, 50002)/g}' "$CUSTOMSERVER"

    if grep -q "50000, 50002" "$CUSTOMSERVER"; then
        echo "customserver.py: get_random_port() range set to 50000–50002"
    else
        echo "Failed: Could not verify customserver.py patch — check $CUSTOMSERVER manually."
    fi
fi
# ------------------------------------------------------------------------------------------------------------------------------------------------------------

# Build and Start Docker
echo ""
echo "Starting Docker containers"
cd "$DEPLOY_DIR"

COMPOSE_CMD="docker compose"

$COMPOSE_CMD up -d --build

# Read host from config.yaml for the completion message
CONFIG_HOST="$(grep -E '^\s*host\s*:' "$SCRIPT_DIR/config.yaml" | sed 's/.*:\s*//' | tr -d '"'"'"' ' | head -1)"
DISPLAY_HOST="${CONFIG_HOST:-localhost}"

echo "Deployment done!"

