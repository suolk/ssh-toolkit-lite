#!/bin/bash
set -euo pipefail

MODE=""
DOMAIN="${1:-}"
WEBROOT_PATH="/var/www/html"
ENCRYPT_DIR="/etc/encrypt"
ACME_PATH="${HOME}/.acme.sh/acme.sh"
if [ ! -f "$ACME_PATH" ]; then
    ACME_PATH="/root/.acme.sh/acme.sh"
fi

checkPort80() {
    echo "[INFO] Checking port 80 usage..."
    local port_80_pids
    port_80_pids=$(lsof -ti :80 || true)
    if [ -z "$port_80_pids" ]; then
        echo "[OK] Port 80 is free, using standalone mode..."
        MODE="standalone"
    else
        echo "[ERROR] Port 80 is in use by:"
        echo "======================================"
        lsof -i :80 || true
        echo "======================================"
        echo "[INFO] Please choose another method."
    fi
}

checkNginx() {
    if systemctl is-active --quiet nginx; then
        echo "[INFO] Nginx is running, using webroot mode..."
        if [ ! -d "$WEBROOT_PATH" ]; then
            echo "[ERROR] Webroot path $WEBROOT_PATH does not exist."
        else
            MODE="webroot"
        fi
    else
        echo "[ERROR] Nginx is not running."
    fi
}

checkCFToken() {
    read -r -s -p "Enter Cloudflare API Token: " CF_Token
    echo  # 补换行
    export CF_Token
    local resp
    resp=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
        -H "Authorization: Bearer $CF_Token" \
        -H "Content-Type: application/json")

    if echo "$resp" | grep -q '"success":true'; then
        echo "[INFO] Cloudflare API Token is valid, using DNS-01 mode..."
        MODE="dns"
    else
        echo "[ERROR] Invalid Cloudflare API Token."
    fi
}

if [ -z "$DOMAIN" ]; then
    echo "Domain is required as an argument. Usage: $0 <domain>"
    exit 1
fi

if [ ! -d "$ENCRYPT_DIR/$DOMAIN" ]; then
    mkdir -p "$ENCRYPT_DIR/$DOMAIN" || {
        echo "failed to create encrypt directory"
        exit 1
    }
else
    if [ -f "$ENCRYPT_DIR/$DOMAIN/privkey.pem" ] && \
       [ -f "$ENCRYPT_DIR/$DOMAIN/fullchain.pem" ] && \
       openssl x509 -in "$ENCRYPT_DIR/$DOMAIN/fullchain.pem" -checkend 1296000 -noout; then
        echo "Certificate for $DOMAIN is still valid, skipping installation."
        exit 0
    fi
fi

if [ ! -f "$ACME_PATH" ]; then
    echo "acme.sh is not installed, installing..."
    curl -s https://get.acme.sh | sh
fi

while [ -z "$MODE" ]; do
    echo "1 use standalone mode (requires port 80)"
    echo "2 use webroot mode (requires nginx)"
    echo "3 use DNS-01 mode (Cloudflare API Token required)"
    echo "4 exit"
    read -r -p "Choose a method to obtain certificate: " method
    case "$method" in
    1) checkPort80 ;;
    2) checkNginx ;;
    3) checkCFToken ;;
    4) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid method. Please choose 1, 2, 3, or 4." ;;
    esac
done

$ACME_PATH --register-account 2>/dev/null || true
$ACME_PATH --set-default-ca --server letsencrypt
$ACME_PATH --install-cronjob

if [ "$MODE" == "standalone" ]; then
    $ACME_PATH --issue -d "$DOMAIN" --standalone
elif [ "$MODE" == "webroot" ]; then
    $ACME_PATH --issue -d "$DOMAIN" --webroot "$WEBROOT_PATH"
elif [ "$MODE" == "dns" ]; then
    $ACME_PATH --issue -d "$DOMAIN" --dns dns_cf
fi

mkdir -p "$ENCRYPT_DIR/$DOMAIN"
$ACME_PATH --install-cert -d "$DOMAIN" \
    --key-file       "$ENCRYPT_DIR/$DOMAIN/privkey.pem" \
    --fullchain-file "$ENCRYPT_DIR/$DOMAIN/fullchain.pem"

echo "Done:"
echo "  Cert: $ENCRYPT_DIR/$DOMAIN/fullchain.pem"
echo "  Key : $ENCRYPT_DIR/$DOMAIN/privkey.pem"