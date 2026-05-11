CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="$CONFIG_DIR/config.json"
HY2_PATH="$CONFIG_DIR/hysteria2/config.json"
VLESS_PATH="$CONFIG_DIR/vless/config.json"
SHARE_LINK_PATH="$CONFIG_DIR/share_link.txt"

hy2_config=$(cat "$HY2_PATH" 2>/dev/null || true)
vless_config=$(cat "$VLESS_PATH" 2>/dev/null || true)
cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
        $hy2_config,
        $vless_config
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
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
