#!/usr/bin/env bash
# Bootstrap a freshly-imaged Pi: copies the persistent reverse-tunnel keypair
# and the magic-link UUID from the laptop, rsyncs the repo, then runs
# provision.sh on the Pi.
#
# Usage: pi/bootstrap.sh photobooth@photobooth.local
#
# Pi-side prerequisites (do these BEFORE running this script):
#   1. Flash Pi OS Lite via Pi Imager. Advanced options: hostname=photobooth,
#      user=photobooth, SSH on, WiFi creds.
#   2. ssh-copy-id photobooth@photobooth.local      (or your laptop's pubkey)
#
# Persistent secrets (laptop-side, gitignored at pi/secrets/):
#   - tunnel_key / tunnel_key.pub  : reverse-tunnel ed25519 keypair. The pubkey
#                                    is baked into king's k3s `photobooth`
#                                    ConfigMap (~/Source/ultros/k3s/photobooth.yaml,
#                                    field `data.authorized_keys`). Do NOT
#                                    rotate without updating that file and
#                                    re-applying it on king.
#   - auth_uuid                    : the magic-link token. Visitors get to the
#                                    UI at https://photobooth.ulyssepence.com/<uuid>.
#                                    Static; never rotates on reimage.
# If any of these are missing this script generates a new one ONCE and warns.
#
# King-side one-time setup (already done; documented for re-bootstrap):
#   a. Generate sshd host keys onto the `data` PVC so they survive pod restarts:
#        ssh king kubectl exec data-shell -- sh -c '
#          mkdir -p /data/photobooth/host_keys && cd /data/photobooth/host_keys &&
#          ssh-keygen -t ed25519 -N "" -f ssh_host_ed25519_key -C photobooth-host &&
#          ssh-keygen -t rsa -b 3072 -N "" -f ssh_host_rsa_key   -C photobooth-host'
#   b. Apply the manifest (mounts those keys into the photobooth pod):
#        scp ~/Source/ultros/k3s/photobooth.yaml king:/tmp/ &&
#        ssh king kubectl apply -f /tmp/photobooth.yaml
#      The pod is named `photobooth` (deployment + configmap + service).
#   c. After the host keys exist on the PVC, the pod's sshd serves a stable
#      fingerprint, so the Pi's autossh tunnel won't break on pod restarts.
#      The tunnel unit also passes -o StrictHostKeyChecking=no for safety.
set -euo pipefail

target="${1:?usage: bootstrap.sh user@host}"
here="$(cd "$(dirname "$0")" && pwd)"
secrets="$here/secrets"
key="$secrets/tunnel_key"
uuid="$secrets/auth_uuid"

mkdir -p "$secrets"
chmod 700 "$secrets"
if [[ ! -f "$key" ]]; then
  echo "==> generating new tunnel keypair at $key (one-time)"
  ssh-keygen -t ed25519 -N "" -f "$key" -C photobooth-tunnel
  echo
  echo "!!! NEW KEY — paste the pubkey below into king's photobooth ConfigMap:"
  cat "$key.pub"
  echo
fi
if [[ ! -f "$uuid" ]]; then
  echo "==> generating new auth UUID at $uuid (one-time)"
  uuidgen | tr -d '\n' > "$uuid"
  chmod 600 "$uuid"
  echo "    magic link: https://photobooth.ulyssepence.com/$(cat "$uuid")"
fi

echo "==> rsync repo"
rsync -az --delete \
  --exclude '.venv' --exclude '__pycache__' --exclude 'data' \
  --exclude 'output' --exclude '.pytest_cache' --exclude 'secrets' \
  "$here/" "$target:photobooth/pi/"

echo "==> install secrets into /etc/photobooth"
scp "$key" "$key.pub" "$uuid" "$target:/tmp/"
ssh "$target" "sudo install -d -o photobooth -g photobooth -m 700 /etc/photobooth && \
                sudo install -o photobooth -g photobooth -m 600 /tmp/tunnel_key /etc/photobooth/tunnel_key && \
                sudo install -o photobooth -g photobooth -m 644 /tmp/tunnel_key.pub /etc/photobooth/tunnel_key.pub && \
                sudo install -o photobooth -g photobooth -m 600 /tmp/auth_uuid /etc/photobooth/auth_uuid && \
                rm /tmp/tunnel_key /tmp/tunnel_key.pub /tmp/auth_uuid"

echo "==> run provision.sh"
ssh "$target" "sudo bash photobooth/pi/provision.sh"
