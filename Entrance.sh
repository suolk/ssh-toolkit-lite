#!/bin/bash
set -euo pipefail

APT_UPDATED=0
PM=""

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PM="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PM="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PM="yum"
  elif command -v pacman >/dev/null 2>&1; then
    PM="pacman"
  elif command -v apk >/dev/null 2>&1; then
    PM="apk"
  elif command -v zypper >/dev/null 2>&1; then
    PM="zypper"
  else
    echo "No supported package manager found." >&2
    exit 1
  fi
}

get_package_name() {
  local cmd="$1"
  case "$cmd" in
    getent)
      case "$PM" in
        apt) echo "libc-bin" ;;
        dnf|yum) echo "glibc-common" ;;
        pacman) echo "glibc" ;;
        apk) echo "musl-utils" ;;
        zypper) echo "glibc" ;;
      esac
      ;;
    ss)
      case "$PM" in
        apt) echo "iproute2" ;;
        dnf|yum) echo "iproute" ;;
        pacman) echo "iproute2" ;;
        apk) echo "iproute2" ;;
        zypper) echo "iproute2" ;;
      esac
      ;;
    shuf)
      echo "coreutils"
      ;;
    uuidgen)
      case "$PM" in
        apt) echo "util-linux" ;;
        dnf|yum) echo "util-linux" ;;
        pacman) echo "util-linux" ;;
        apk) echo "util-linux" ;;
        zypper) echo "util-linux" ;;
      esac
      ;;
  esac
}

install_package() {
  local pkg="$1"
  case "$PM" in
    apt)
      if [ "$APT_UPDATED" -eq 0 ]; then
        apt-get update -y
        APT_UPDATED=1
      fi
      apt-get install -y "$pkg"
      ;;
    dnf)
      dnf install -y "$pkg"
      ;;
    yum)
      yum install -y "$pkg"
      ;;
    pacman)
      pacman -Sy --noconfirm "$pkg"
      ;;
    apk)
      apk add --no-cache "$pkg"
      ;;
    zypper)
      zypper --non-interactive install "$pkg"
      ;;
  esac
}

ensure_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  local pkg
  pkg=$(get_package_name "$cmd")
  if [ -z "${pkg:-}" ]; then
    echo "No package mapping found for $cmd." >&2
    exit 1
  fi
  echo "$cmd not found. Installing $pkg..."
  install_package "$pkg"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd still not available after install." >&2
    exit 1
  fi
}

ensure_dependencies() {
  detect_package_manager
  ensure_command getent
  ensure_command ss
  ensure_command shuf
  ensure_command uuidgen
}

ensure_dependencies
while true; do
  echo ""
  echo "=============================="
  echo "        Main Menu"
  echo "=============================="
  echo "1) Change SSH port"
  echo "2) Install Nginx"
  echo "3) Install sing-box"
  echo "4) Deploy sing-box + Hysteria2 (requires domain)"
  echo "5) Deploy sing-box + Vless (requires domain)"
  echo "6) Deploy Vless + Reality (not available)"
  echo "7) Exit"
  echo "=============================="

  read -r -p "Select option: " choice
  case "$choice" in
    1)
      bash Command/setSSHDPort.sh || echo "[ERROR] SSH port change failed" ;;
    2)
      bash Command/installNginx.sh || echo "[ERROR] Nginx install failed" ;;
    3)
      bash Command/installSingbox.sh || echo "[ERROR] sing-box install failed" ;;
    4)
      bash Command/installSingbox.sh || true
      bash Command/confHy2.sh || echo "[ERROR] Hysteria2 config failed" 
      bash Command/confSingbox.sh || echo "[ERROR] sing-box config failed" ;;
    5)
      bash Command/installSingbox.sh || true
      bash Command/confVless.sh || echo "[ERROR] VLESS config failed" 
      bash Command/confSingbox.sh || echo "[ERROR] sing-box config failed" ;;
    6)
      echo "[ERROR] Reality setup is not available in this release." ;;
    7)
      exit 0 ;;
    *)
      echo "Invalid choice." ;;
  esac
done
