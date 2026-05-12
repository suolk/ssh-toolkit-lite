#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
fi

echo "=============================="
echo "  sing-box Uninstall Tool"
echo "=============================="
echo ""

echo "[1/5] Stopping and removing sing-box service..."
systemctl stop sing-box 2>/dev/null || true
systemctl disable sing-box 2>/dev/null || true
rm -f /etc/systemd/system/sing-box.service
rm -rf /etc/systemd/system/sing-box.service.d
systemctl daemon-reload

echo "[2/5] Removing sing-box binary..."
rm -f /usr/local/bin/sing-box

echo "[3/5] Removing all sing-box configs..."
rm -rf /etc/sing-box

echo ""
read -r -p "Remove certificates (/etc/encrypt)? (y/n) " remove_certs
if [[ "$remove_certs" =~ ^[Yy]$ ]]; then
    echo "[4/5] Removing certificates..."
    rm -rf /etc/encrypt
else
    echo "[4/5] Skipped."
fi

echo ""
read -r -p "Remove acme.sh? (y/n) " remove_acme
if [[ "$remove_acme" =~ ^[Yy]$ ]]; then
    echo "Removing acme.sh..."
    rm -rf /root/.acme.sh ~/.acme.sh 2>/dev/null || true
    crontab -l 2>/dev/null | grep -v acme.sh | crontab - 2>/dev/null || true
else
    echo "Skipped."
fi

echo ""
read -r -p "Remove Nginx? (y/n) " remove_nginx
if [[ "$remove_nginx" =~ ^[Yy]$ ]]; then
    echo "[5/5] Removing Nginx..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    if command -v apt-get >/dev/null 2>&1; then
        apt-get purge -y nginx nginx-common nginx-core 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y nginx 2>/dev/null || true
    elif command -v apk >/dev/null 2>&1; then
        apk del nginx 2>/dev/null || true
    fi
    rm -rf /etc/nginx /var/www/html 2>/dev/null || true
else
    echo "[5/5] Skipped."
fi

echo ""
echo "=============================="
echo "  Uninstall complete."
echo "=============================="