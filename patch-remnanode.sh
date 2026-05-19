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

    python3 - "$COMPOSE_FILE" << 'PYEOF'
import sys, re

path = sys.argv[1]

with open(path, 'r') as f:
    content = f.read()

new_volumes = (
    "      - /etc/letsencrypt/live/${XRAY_DOMAIN}/fullchain.pem:/etc/xray/certs/fullchain.pem:ro\n"
    "      - /etc/letsencrypt/live/${XRAY_DOMAIN}/privkey.pem:/etc/xray/certs/privkey.pem:ro"
)

# Find remnanode service block and its volumes section, insert after last existing volume
# Strategy: find "      - /etc/letsencrypt:/etc/letsencrypt:ro" and append after it
target = "      - /etc/letsencrypt:/etc/letsencrypt:ro"

if target not in content:
    print("ERROR: Could not find anchor line in docker-compose.yml")
    print(f"Expected: {target}")
    sys.exit(1)

# Replace only first occurrence (in remnanode service)
content = content.replace(target, target + "\n" + new_volumes, 1)

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
