#!/bin/bash
set -euo pipefail

UFW_INIT_FLAG="/var/lib/ssh-toolkit-lite/ufw-default-ports.initialized"

echo "Checking for UFW (Uncomplicated Firewall)..."
if command -v ufw >/dev/null 2>&1; then
    echo "UFW is already installed."
else
    echo "UFW not found, installing..."
    sudo apt update
    sudo apt install -y ufw || {
        echo "Failed to install UFW"
        exit 1
    }
fi
echo "Checking if UFW is active..."
if ufw status | grep -q "^Status:active"; then
    echo "UFW is active."
else
    if [ ! -f "$UFW_INIT_FLAG" ]; then
        echo "Allowing default TCP ports 22, 80, and 443 before first UFW enable..."
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo mkdir -p "$(dirname "$UFW_INIT_FLAG")"
        sudo touch "$UFW_INIT_FLAG"
    else
        echo "UFW default ports were already initialized, skipping automatic 22/80/443 rules."
    fi

    sudo ufw --force enable || {
        echo "Failed to enable UFW"
        exit 1
    }
    echo "UFW has been enabled successfully."
fi

while true; do
    echo ""
    echo "====== UFW Manager ======"
    echo "1) Show status"
    echo "2) Add rule"
    echo "3) Delete rule"
    echo "0) Exit"
    echo "========================"
    
    read -p "Choose an option: " opt

    case $opt in
        1)
            sudo ufw status numbered
            ;;
        2)
            echo "Warning: Adding a rule may affect your server's security. Make sure you understand the implications before proceeding."
            read -p "Enter port (e.g. 80 or 22/tcp): " port
            sudo ufw allow "$port"
            ;;
        3)
            echo "Warning: Deleting a rule may block yourself from accessing your server. Make sure you left at least one rule allowing access."
            sudo ufw status numbered
            read -p "Enter rule number(The num between [ ] ) to delete: " num
            sudo ufw delete "$num"
            sudo ufw status numbered
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
done
