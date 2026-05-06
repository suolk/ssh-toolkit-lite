#!/bin/bash
set -euo pipefail

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
