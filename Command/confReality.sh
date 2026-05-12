#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/sing-box/reality"
CONFIG_PATH="$CONFIG_DIR/config.json"
PORT_PATH="$CONFIG_DIR/port.txt"
KEY_PATH="$CONFIG_DIR/keypair.txt"
SHARE_LINK_PATH="$CONFIG_DIR/share_link.txt"

# Common CDN / well-known domains that won't get blocked
DEFAULT_DEST_DOMAINS=(
    "www.microsoft.com"
    "www.apple.com"
    "www.cloudflare.com"
    "www.amazon.com"
    "swdist.apple.com"
    "cdn.jsdelivr.net"
)

getDestDomain() {
    echo "Choose a destination domain for Reality (the server your traffic will pretend to be):"
    for i in "${!DEFAULT_DEST_DOMAINS[@]}"; do
        echo "  $((i + 1))) ${DEFAULT_DEST_DOMAINS[$i]}"
    done
    echo "  0) Enter custom domain"
    read -r -p "Choice [1-${#DEFAULT_DEST_DOMAINS[@]} or 0]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#DEFAULT_DEST_DOMAINS[@]}" ]; then
        destDomain="${DEFAULT_DEST_DOMAINS[$((choice - 1))]}"
    else
        while true; do
            read -r -p "Enter custom destination domain: " destDomain
            if getent hosts "$destDomain" > /dev/null 2>&1; then
                break
            fi
            echo "Domain cannot be resolved, try again." >&2
        done
    fi

    echo "Destination domain: $destDomain"
    read -r -p "Server port for destination [443]: " destPort
    destPort="${destPort:-443}"
    if ! [[ "$destPort" =~ ^[0-9]+$ ]] || [ "$destPort" -lt 1 ] || [ "$destPort" -gt 65535 ]; then
        echo "Invalid port, using 443." >&2
        destPort=443
    fi

    cat > "$CONFIG_DIR/dest.txt" <<EOF
$destDomain
$destPort
EOF
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

generateKeypair() {
    if [ -f "$KEY_PATH" ] && [ -s "$KEY_PATH" ]; then
        echo "Existing keypair found:"
        cat "$KEY_PATH"
        read -r -p "Reuse existing keypair? (y/n) " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    if ! command -v sing-box >/dev/null 2>&1; then
        echo "[ERROR] sing-box not found. Please install sing-box first." >&2
        exit 1
    fi

    echo "Generating Reality keypair..."
    local keypair
    keypair=$(sing-box generate reality-keypair)
    echo "$keypair" > "$KEY_PATH"
    echo "$keypair"
}

deployReality() {
    local destDomain destPort
    destDomain=$(head -1 "$CONFIG_DIR/dest.txt")
    destPort=$(tail -1 "$CONFIG_DIR/dest.txt")
    local newPort
    newPort=$(cat "$PORT_PATH")
    local publicIP
    publicIP=$(curl -4 -fsS https://api.ipify.org || echo "YOUR_SERVER_IP")

    local uuid
    if command -v sing-box >/dev/null 2>&1; then
        uuid=$(sing-box generate uuid)
    else
        uuid=$(uuidgen)
    fi

    local privateKey publicKey
    privateKey=$(grep "PrivateKey" "$KEY_PATH" | awk '{print $2}')
    publicKey=$(grep "PublicKey" "$KEY_PATH" | awk '{print $2}')

    local shortId="6ba85179e30d4fc2"

    cat > "$CONFIG_PATH" <<EOF
{
  "type": "vless",
  "listen": "::",
  "listen_port": $newPort,
  "tag": "VLESSReality",
  "users": [
    {
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "name": "${uuid%%-*}-VLESS_Reality_Vision"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "$destDomain",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "$destDomain",
        "server_port": $destPort
      },
      "private_key": "$privateKey",
      "short_id": [
        "",
        "$shortId"
      ]
    }
  }
}
EOF

    local shareLink="vless://${uuid}@${publicIP}:${newPort}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&sni=${destDomain}&fp=chrome&pbk=${publicKey}&sid=${shortId}#${uuid%%-*}-VLESS_Reality_Vision"
    echo "$shareLink" > "$SHARE_LINK_PATH"

    echo ""
    echo "==================== Reality Config ===================="
    echo "Public Key : $publicKey"
    echo "Short ID   : $shortId"
    echo "Dest       : $destDomain:$destPort"
    echo "Port       : $newPort"
    echo "UUID       : $uuid"
    echo ""
    echo "Share link saved to: $SHARE_LINK_PATH"
}

mkdir -p "$CONFIG_DIR" || {
    echo "failed to create config directory"
    exit 1
}

getDestDomain
getNewPort
generateKeypair
deployReality
