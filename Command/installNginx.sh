#!/bin/bash
set -euo pipefail

# Checking if Nginx is already installed
if command -v nginx >/dev/null 2>&1; then
    echo "Nginx is already installed."
else
    echo "installing Nginx..."
    sudo apt update
    sudo apt install -y nginx || {
        echo "Failed to install Nginx"
        exit 1
    }
fi

# Ensure Nginx is running and enabled on boot
sudo systemctl enable --now nginx || {
    echo "Failed to start/enable Nginx"
    exit 1
}