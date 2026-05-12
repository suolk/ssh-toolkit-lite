CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="$CONFIG_DIR/config.json"
HY2_PATH="$CONFIG_DIR/hysteria2/config.json"
VLESS_PATH="$CONFIG_DIR/vless/config.json"
SHARE_LINK_PATH="$CONFIG_DIR/share_link.txt"
HY2_PORT_PATH="$CONFIG_DIR/hysteria2/port.txt"
VLESS_PORT_PATH="$CONFIG_DIR/vless/port.txt"
HY2_SHARE_LINK_PATH="$CONFIG_DIR/hysteria2/share_link.txt"
VLESS_SHARE_LINK_PATH="$CONFIG_DIR/vless/share_link.txt"

hy2_config=$(cat "$HY2_PATH" 2>/dev/null || true)
vless_config=$(cat "$VLESS_PATH" 2>/dev/null || true)
if [ -n "$hy2_config" ] && [ -n "$vless_config" ]; then
    inbounds_config="        $hy2_config,
        $vless_config"
elif [ -n "$hy2_config" ]; then
    inbounds_config="        $hy2_config"
elif [ -n "$vless_config" ]; then
    inbounds_config="        $vless_config"
else
    echo "[ERROR] No inbound config found." >&2
    exit 1
fi
cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
$inbounds_config
  ]
}
EOF

singbox_bin=$(command -v sing-box)
if ! systemctl cat sing-box >/dev/null 2>&1; then
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target nss-lookup.target

[Service]
ExecStart=$singbox_bin run -c $CONFIG_PATH
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
elif ! systemctl cat sing-box | grep -q -- "-c $CONFIG_PATH"; then
    mkdir -p /etc/systemd/system/sing-box.service.d
    cat > /etc/systemd/system/sing-box.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=$singbox_bin run -c $CONFIG_PATH
EOF
    systemctl daemon-reload
fi
systemctl restart sing-box
echo "[OK] sing-box restarted with $CONFIG_PATH"

if [ -s "$HY2_PORT_PATH" ]; then
    hy2_port=$(cat "$HY2_PORT_PATH")
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            ufw allow "$hy2_port/udp"
            echo "[OK] Allowed Hysteria2 UDP port $hy2_port in ufw."
        else
            echo "[INFO] ufw is inactive, skipped local firewall rule for UDP port $hy2_port."
        fi
    else
        echo "[INFO] ufw is not installed, skipped local firewall rule for UDP port $hy2_port."
    fi
fi

if [ -s "$VLESS_PORT_PATH" ]; then
    vless_port=$(cat "$VLESS_PORT_PATH")
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            ufw allow "$vless_port/tcp"
            echo "[OK] Allowed VLESS TCP port $vless_port in ufw."
        else
            echo "[INFO] ufw is inactive, skipped local firewall rule for TCP port $vless_port."
        fi
    else
        echo "[INFO] ufw is not installed, skipped local firewall rule for TCP port $vless_port."
    fi
fi

if [ -s "$HY2_SHARE_LINK_PATH" ]; then
    echo "Hysteria2 share link:"
    cat "$HY2_SHARE_LINK_PATH"
fi

if [ -s "$VLESS_SHARE_LINK_PATH" ]; then
    echo "VLESS share link:"
    cat "$VLESS_SHARE_LINK_PATH"
fi
