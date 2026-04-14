#!/usr/bin/env bash
# Usage: pi/deploy.sh photobooth@photobooth.local
set -euo pipefail
target="${1:?usage: deploy.sh user@host}"
here="$(cd "$(dirname "$0")" && pwd)"

rsync -az --delete \
  --exclude '.venv' --exclude '__pycache__' --exclude 'data' \
  --exclude 'output' --exclude '.pytest_cache' --exclude 'secrets' \
  "$here/" "$target:photobooth/pi/"

ssh "$target" "cd photobooth/pi && .venv/bin/pip install -q -e . 2>/dev/null || true; sudo systemctl restart photobooth && sleep 2 && systemctl is-active photobooth"
