#!/bin/bash
set -euo pipefail

UFW_INIT_FLAG="/var/lib/ssh-toolkit-lite/ufw-default-ports.initialized"

change_ssh_port() {
    local new_port
    local ssh_config="/etc/ssh/sshd_config"
    local ssh_service

    read -r -p "Enter new SSH port (1024-65535): " new_port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
        echo "Invalid port. Please enter a number between 1024 and 65535."
        return 1
    fi

    echo "Allowing new SSH port $new_port/tcp in UFW first..."
    sudo ufw allow "$new_port/tcp"

    if grep -qE '^#?Port[[:space:]]+[0-9]+' "$ssh_config"; then
        sudo sed -i "s/^#\?Port[[:space:]]\+[0-9]\+/Port $new_port/" "$ssh_config"
    else
        echo "Port $new_port" | sudo tee -a "$ssh_config" >/dev/null
    fi

    sudo sshd -t || {
        echo "sshd config test failed. Reverting the port change is recommended." >&2
        return 1
    }

    sudo systemctl restart sshd ||  echo "Failed to restart sshd."
    sudo systemctl restart ssh ||  echo "Failed to restart ssh." 

    echo "[OK] SSH port changed to $new_port."
    echo "[INFO] Verify the new port works before deleting the old SSH rule."
}

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
    echo "====== UFW / SSH Manager ======"
    echo "1) Show UFW status"
    echo "2) Add UFW rule"
    echo "3) Delete UFW rule"
    echo "4) Change SSH port"
    echo "0) Exit"
    echo "================================"
    
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
        4)
            change_ssh_port
            ;;
        0)
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
done
