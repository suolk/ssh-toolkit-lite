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

if ! systemctl cat sing-box | grep -q -- "-c $CONFIG_PATH"; then
    singbox_bin=$(command -v sing-box)
    mkdir -p /etc/systemd/system/sing-box.service.d
    cat > /etc/systemd/system/sing-box.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=$singbox_bin run -c $CONFIG_PATH
EOF
    systemctl daemon-reload
fi
systemctl restart sing-box
