#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/sing-box/hysteria2"
CONFIG_PATH="$CONFIG_DIR/config.json"
DOMAIN_PATH="$CONFIG_DIR/domain.txt"
PORT_PATH="$CONFIG_DIR/port.txt"
SHARE_LINK_PATH="$CONFIG_DIR/share_link.txt"
ENCRYPT_DIR="/etc/encrypt"

getDomain() {
    # Check if there is already a domain saved
    local domain=""
    if [ -f "$DOMAIN_PATH" ] && [ -s "$DOMAIN_PATH" ]; then
        domain=$(cat "$DOMAIN_PATH")
    fi
    # If domain exists, ask user if they want to keep it
    if [ -n "$domain" ]; then
        echo "Current domain: $domain"
        echo "Do you want to change the current domain? (y/n) "
        read -r -p " "answer
        if ! [[ "$answer" =~ ^[Nn]$ ]]; then
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

getNewPort(){
    # Generate random port
    local newPort
    local port_in_use
    newPort=$(cat "$PORT_PATH" 2>/dev/null || true)
    port_in_use=$(ss -lnt | grep ":$newPort" || true)
    while ! [ -z "$port_in_use" ]; do
        newPort=$(shuf -i 1024-65535 -n 1)
        port_in_use=$(ss -lnt | grep ":$newPort" || true)
    done
    echo "Generated random port: $newPort"
    # Ask user if they want to change the random port
    echo "Do you want to change the random port? (y/n) "
    read -r -p " " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        while true; do
            read -r -p "Enter new port (1024-65535): " newPort
            port_in_use=$(ss -lnt | grep ":$newPort" || true)
            if [[ "$newPort" =~ ^[0-9]+$ ]] && [ "$newPort" -ge 1024 ] && [ "$newPort" -le 65535 ] && [ -z "$port_in_use" ]; then
                break
            else
                echo "Invalid port. Please enter a number between 1024 and 65535."
            fi
        done
    fi
    echo "$newPort" > "$PORT_PATH"
}

deployHysteria2() {
    local password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
    local password_obfs=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
    local username="client-$(tr -dc '0-9' </dev/urandom | head -c 2)"
    local domain=$(cat "$DOMAIN_PATH")
    local newPort=$(cat "$PORT_PATH")
    
    cat > "$CONFIG_PATH" <<EOF
{
    "type": "hysteria2",
    "tag": "hy2-out",
    "listen": "0.0.0.0",
    "listen_port": $newPort,
    "up_mbps": 50,
    "down_mbps": 100,
    "obfs": {
        "type": "salamander",
        "password": "$password_obfs"
    },
    "users": [
    {
        "name": "$username",
        "password": "$password"
    }
    ],
    "ignore_client_bandwidth": false,
    "tls": {
    "enabled": true,
    "certificate_path": "$ENCRYPT_DIR/$domain/fullchain.pem",
    "key_path": "$ENCRYPT_DIR/$domain/privkey.pem"
    }
}
EOF
    local shareLink="hysteria2://${domain}:${newPort}?password=${password}&obfs=${password_obfs}#Hysteria2"
    echo "$shareLink" > "$SHARE_LINK_PATH"
}

mkdir -p "$CONFIG_DIR"
getNewPort
getDomain
deployHysteria2
