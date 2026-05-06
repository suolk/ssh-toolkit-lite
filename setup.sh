#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_URL="https://github.com/suolk/ssh-toolkit-lite/archive/refs/heads/main.tar.gz"
WORKDIR="$(mktemp -d)"

cleanup() {
	rm -rf "$WORKDIR"
}

trap cleanup EXIT INT TERM

cd "$WORKDIR"
wget -O SSH-Toolkit-Lite.tar.gz "$ARCHIVE_URL"
tar -xzf SSH-Toolkit-Lite.tar.gz
cd SSH-Toolkit-Lite-main
bash Entrance.sh