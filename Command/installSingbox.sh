#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found, installing..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y jq
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release
        yum install -y jq
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y jq
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache jq
    else
        echo "No supported package manager found. Please install jq manually."
    fi
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "jq installation failed. Please install jq manually and retry."
    exit 1
fi
SINGBOX_PATH="/usr/local/bin/sing-box"
TMP_DIR="/tmp/sing-box"
TMP_PATH="$TMP_DIR/sing-box.tar.gz"

ARCH=$(uname -m)
# get system architecture
case "$ARCH" in
    x86_64)
        FILE_ARCH="amd64"
        ;;
    aarch64 | arm64)
        FILE_ARCH="arm64"
        ;;
    *)
        echo "unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Check if sing-box installed
if command -v sing-box >/dev/null 2>&1; then
    echo "sing-box is already installed."
    SINGBOX_PATH=$(command -v sing-box)
elif [ -f "$SINGBOX_PATH" ]; then
    echo "sing-box found at $SINGBOX_PATH"
else
    echo "sing-box not found."
    rm -rf "$TMP_DIR" || {
        echo "failed to clean up temporary directory"
        exit 1
    }
    mkdir -p "$TMP_DIR" || {
        echo "failed to create temporary directory"
        exit 1
    }

    echo "downloading..."
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r ".assets[] | select(.name | test(\"linux-${FILE_ARCH}\\\\.tar\\\\.gz$\")) | .browser_download_url")
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "failed to get download URL for sing-box"
        exit 1
    fi
    curl -fL -o "$TMP_PATH" "$DOWNLOAD_URL"|| {
        echo "download failed: $DOWNLOAD_URL"
        exit 1
    }
    echo "unzipping..."
    tar -xzf "$TMP_PATH" -C "$TMP_DIR" || {
        echo "failed to unzip sing-box"
        exit 1
    }
    SINGBOX_BIN=$(find "$TMP_DIR" -type f -name sing-box| head -n 1)
    if [ -z "$SINGBOX_BIN" ]; then
        echo "failed to find sing-box binary after unzipping"
        exit 1
    fi
    echo "installing..."
    install -m 755 "$SINGBOX_BIN" "$SINGBOX_PATH" || {
        echo "installation failed"
        exit 1
    }
    rm -rf "$TMP_DIR"
fi
