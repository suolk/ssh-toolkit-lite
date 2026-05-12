#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/sing-box/vless"
CONFIG_PATH="$CONFIG_DIR/config.json"
DOMAIN_PATH="$CONFIG_DIR/domain.txt"
PORT_PATH="$CONFIG_DIR/port.txt"
SHARE_LINK_PATH="$CONFIG_DIR/share_link.txt"
DEFAULT_ENCRYPT_DIR="/etc/encrypt"
ALT_ENCRYPT_DIR="/etc/encryptR"

validateDomainIp() {
    local domain="$1"
    local public_ip
    local domain_ips

    public_ip=$(curl -4 -fsS https://api.ipify.org || true)
    if [ -z "$public_ip" ]; then
        echo "[WARN] Could not detect public IPv4, skipped domain IP check."
        return 0
    fi

    domain_ips=$(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u)
    if ! echo "$domain_ips" | grep -qx "$public_ip"; then
        echo "[ERROR] Domain $domain does not resolve to this server IP ($public_ip)." >&2
        echo "Resolved IPv4: ${domain_ips:-none}" >&2
        return 1
    fi
}

getNewPort() {
    local newPort
    local port_in_use
    newPort=$(cat "$PORT_PATH" 2>/dev/null || true)
    port_in_use=$(ss -lnt | grep ":$newPort" || true)
    while [ -z "${newPort:-}" ] || [ -n "$port_in_use" ]; do
        newPort=$(shuf -i 1024-65535 -n 1)
        port_in_use=$(ss -lnt | grep ":$newPort" || true)
    done

    echo "Generated random port: $newPort"
    read -r -p "Do you want to change the random port? (y/n) " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        while true; do
            read -r -p "Enter new port (1024-65535): " newPort
            port_in_use=$(ss -lnt | grep ":$newPort" || true)
            if [[ "$newPort" =~ ^[0-9]+$ ]] && [ "$newPort" -ge 1024 ] && [ "$newPort" -le 65535 ] && [ -z "$port_in_use" ]; then
                break
            else
                echo "Invalid port. Please enter an unused number between 1024 and 65535."
            fi
        done
    fi
    echo "$newPort" > "$PORT_PATH"
}

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
        elif ! validateDomainIp "$domain"; then
            domain=""
        fi
    done
    echo "$domain" > "$DOMAIN_PATH"

    bash Command/installCert.sh "$domain"
    if [ ! -f "$DEFAULT_ENCRYPT_DIR/$domain/fullchain.pem" ] && [ ! -f "$ALT_ENCRYPT_DIR/$domain/fullchain.pem" ]; then
        echo "Certificate generation failed!">&2
        exit 1
    fi
}

getCertDir() {
    local domain="$1"

    if [ -f "$ALT_ENCRYPT_DIR/$domain/fullchain.pem" ] && [ -f "$ALT_ENCRYPT_DIR/$domain/privkey.pem" ]; then
        echo "$ALT_ENCRYPT_DIR"
        return 0
    fi

    echo "$DEFAULT_ENCRYPT_DIR"
}

deployVless() {
    local domain
    domain=$(cat "$DOMAIN_PATH")
    local newPort
    newPort=$(cat "$PORT_PATH")
    local uuid
    uuid=$(uuidgen)
    local certDir
    certDir=$(getCertDir "$domain")
    local nodeName="${uuid%%-*}-VLESS_TCP/TLS_Vision"

    cat > "$CONFIG_PATH" <<EOF
{
    "type": "vless",
    "tag": "VLESSTCP",
    "listen": "::",
    "listen_port": $newPort,
    "users": [
        {
            "uuid": "$uuid",
            "flow": "xtls-rprx-vision",
            "name": "$nodeName"
        }
    ],
    "tls": {
        "server_name": "$domain",
        "enabled": true,
        "certificate_path": "$certDir/$domain/fullchain.pem",
        "key_path": "$certDir/$domain/privkey.pem"
    }
}
EOF
    local shareLink="vless://$uuid@$domain:$newPort?encryption=none&security=tls&type=tcp&host=$domain&fp=chrome&headerType=none&sni=$domain&flow=xtls-rprx-vision#$nodeName"
    echo "$shareLink" > "$SHARE_LINK_PATH"
}

getNewPort
getDomain
deployVless
