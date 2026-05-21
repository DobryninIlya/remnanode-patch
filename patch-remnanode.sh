#!/bin/bash
set -euo pipefail

COMPOSE_DIR="/opt/remnanode"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
ENV_FILE="$COMPOSE_DIR/.env"
BACKUP_FILE="$COMPOSE_FILE.bak"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Detect domain ---
DOMAIN=""
LE_DIR="/etc/letsencrypt/live"

if [ -d "$LE_DIR" ]; then
    DOMAIN=$(ls "$LE_DIR" 2>/dev/null | grep -v README | head -1)
fi

if [ -z "$DOMAIN" ]; then
    warn "Domain not auto-detected in $LE_DIR"
    read -rp "Enter domain (e.g. node-swed.numerologistic.ru): " DOMAIN
fi

[ -z "$DOMAIN" ] && error "Domain is required"
info "Domain: $DOMAIN"

# --- Validate cert exists ---
CERT_PATH="$LE_DIR/$DOMAIN/fullchain.pem"
KEY_PATH="$LE_DIR/$DOMAIN/privkey.pem"
[ -f "$CERT_PATH" ] || error "Certificate not found: $CERT_PATH"
[ -f "$KEY_PATH" ]  || error "Private key not found: $KEY_PATH"
info "Certificates found"

# --- Validate compose file ---
[ -f "$COMPOSE_FILE" ] || error "docker-compose.yml not found: $COMPOSE_FILE"

# --- Update .env ---
if [ -f "$ENV_FILE" ] && grep -q "^XRAY_DOMAIN=" "$ENV_FILE"; then
    sed -i "s|^XRAY_DOMAIN=.*|XRAY_DOMAIN=$DOMAIN|" "$ENV_FILE"
    info ".env: updated XRAY_DOMAIN=$DOMAIN"
else
    echo "XRAY_DOMAIN=$DOMAIN" >> "$ENV_FILE"
    info ".env: added XRAY_DOMAIN=$DOMAIN"
fi

# --- Patch docker-compose.yml ---
if grep -q "/etc/xray/certs" "$COMPOSE_FILE"; then
    info "docker-compose.yml already patched, skipping"
else
    cp "$COMPOSE_FILE" "$BACKUP_FILE"
    info "Backup saved: $BACKUP_FILE"

    python3 - "$COMPOSE_FILE" "$DOMAIN" << 'PYEOF'
import sys

path = sys.argv[1]
domain = sys.argv[2]

with open(path, 'r') as f:
    content = f.read()

new_volumes = (
    f"      - /etc/letsencrypt/live/{domain}/fullchain.pem:/etc/xray/certs/fullchain.pem:ro\n"
    f"      - /etc/letsencrypt/live/{domain}/privkey.pem:/etc/xray/certs/privkey.pem:ro"
)

# Find remnanode service block by container_name or hostname, then find
# the /dev/shm volume inside that block and insert after it.
# This works regardless of whether /etc/letsencrypt is already mounted.

anchor_service = "container_name: remnanode"
if anchor_service not in content:
    anchor_service = "hostname: remnanode"
if anchor_service not in content:
    print("ERROR: Cannot find remnanode service block in docker-compose.yml")
    sys.exit(1)

service_pos = content.find(anchor_service)

anchor_vol = "      - /dev/shm:/dev/shm:rw"
vol_pos = content.find(anchor_vol, service_pos)

if vol_pos == -1:
    print("ERROR: Cannot find /dev/shm volume in remnanode service block")
    sys.exit(1)

insert_pos = vol_pos + len(anchor_vol)
content = content[:insert_pos] + "\n" + new_volumes + content[insert_pos:]

with open(path, 'w') as f:
    f.write(content)

print("Patched successfully")
PYEOF

    info "docker-compose.yml: added cert volumes to remnanode"
fi

# --- Restart ---
echo ""
read -rp "Restart containers now? [y/N]: " RESTART
if [[ "$RESTART" =~ ^[Yy]$ ]]; then
    cd "$COMPOSE_DIR"
    docker compose down
    docker compose up -d
    info "Containers restarted"
    echo ""
    docker compose ps
fi

# --- Final instructions ---
echo ""
echo "========================================"
echo "  Update Remnawave panel profile config:"
echo "========================================"
echo ""
echo '  "certificates": ['
echo '    {'
echo '      "keyFile": "/etc/xray/certs/privkey.pem",'
echo '      "certificateFile": "/etc/xray/certs/fullchain.pem"'
echo '    }'
echo '  ]'
echo ""
echo "  Remove or leave empty serverName field - xray will use SNI from client"
echo ""
info "Done!"
