#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/sing-box/vless"
CONFIG_PATH="$CONFIG_DIR/config.json"
DOMAIN_PATH="$CONFIG_DIR/domain.txt"
SHARE_LINK_PATH="$CONFIG_DIR/share_link.txt"
ENCRYPT_DIR="/etc/encrypt"

mkdir -p "$CONFIG_DIR" || {
    echo "failed to create config directory"
    exit 1
}

getDomain() {
    # Check if there is already a domain saved
    local domain=""
    if [ -f "$DOMAIN_PATH" ] && [ -s "$DOMAIN_PATH" ]; then
        domain=$(cat "$DOMAIN_PATH")
    fi
    # If domain exists, ask user if they want to keep it
    if [ -n "$domain" ]; then
        echo "Current domain: $domain"
        read -r -p "Do you want to keep the current domain? (y/n) " answer
        if ! [[ "$answer" =~ ^[Yy]$ ]]; then
            domain=""
        fi
    fi
    # If there is no valid domain, prompt user to enter one
    while [ -z "${domain:-}" ]; do
        read -r -p "Enter your domain ( exmaple.com ): " domain
        if ! getent hosts "$domain" > /dev/null; then
            echo "Domain cannot be resolved">&2
            domain=""
        fi
    done
    echo "$domain" > "$DOMAIN_PATH"

    bash Command/installCert.sh "$domain"
    if [ ! -f "$ENCRYPT_DIR/$domain/fullchain.pem" ]; then
        echo "Certificate generation failed!">&2
        exit 1
    fi
}

deployVless() {
    local domain
    domain=$(cat "$DOMAIN_PATH")
    local uuid
    uuid=$(uuidgen)

    cat > "$CONFIG_PATH" <<EOF
{
    "type": "vless",
    "tag": "vless-in",
    "listen": "0.0.0.0",
    "listen_port": 443,
    "users": [
        {
            "uuid": "$uuid"
        }
    ],
    "tls": {
        "enabled": true,
        "server_name": "$domain",
        "certificate_path": "$ENCRYPT_DIR/$domain/fullchain.pem",
        "key_path": "$ENCRYPT_DIR/$domain/privkey.pem"
    }
}
EOF
    local shareLink="vless://$uuid@$domain:443?encryption=none&security=tls&type=tcp&sni=$domain#VLESS-TLS"
    echo "$shareLink" > "$SHARE_LINK_PATH"
}

getDomain
deployVless