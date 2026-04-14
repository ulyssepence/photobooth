#!/usr/bin/env bash
# Idempotent provisioning script for the Raspberry Pi 3B+ photobooth host.
#
# DO NOT run this directly on a fresh Pi. Use `pi/bootstrap.sh` from your
# laptop instead — it copies the persistent secrets (tunnel key + auth UUID)
# into /etc/photobooth/ first, then invokes this script. provision.sh now
# refuses to start if those files are missing.
#
#     pi/bootstrap.sh photobooth@photobooth.local
#
# After re-running on an existing install, no manual follow-ups: the tunnel
# pubkey already lives in king's k3s photobooth ConfigMap, the magic-link
# UUID is static, and CUPS/queue setup is idempotent.
set -euo pipefail

REPO=/home/photobooth/photobooth
APP=$REPO/pi
USER_NAME=photobooth
ETC_DIR=/etc/photobooth
CUPS_VENV=/opt/photobooth-cups
KING_IP=45.56.101.108
TUNNEL_PORT=2226

if [[ $EUID -ne 0 ]]; then
  echo "must run as root (try: sudo bash $0)" >&2
  exit 1
fi

echo "==> apt packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  autossh git python3-venv libusb-1.0-0 uuid-runtime \
  cups cups-bsd avahi-daemon printer-driver-all \
  poppler-utils python3-pil python3-dev libcups2-dev ghostscript

echo "==> groups"
usermod -aG lp,lpadmin "$USER_NAME"

echo "==> /etc/photobooth secrets (generated once, never overwritten)"
install -d -o "$USER_NAME" -g "$USER_NAME" -m 700 "$ETC_DIR"
if [[ ! -f "$ETC_DIR/tunnel_key" ]]; then
  echo "FATAL: $ETC_DIR/tunnel_key missing — run pi/bootstrap.sh from your laptop instead of provision.sh directly" >&2
  exit 1
fi
if [[ ! -f "$ETC_DIR/auth_uuid" ]]; then
  echo "FATAL: $ETC_DIR/auth_uuid missing — run pi/bootstrap.sh from your laptop instead of provision.sh directly" >&2
  exit 1
fi
UUID=$(cat "$ETC_DIR/auth_uuid")

echo "==> photobooth flask venv"
if [[ ! -x "$APP/.venv/bin/python" ]]; then
  sudo -u "$USER_NAME" python3 -m venv "$APP/.venv"
fi
sudo -u "$USER_NAME" "$APP/.venv/bin/pip" install --quiet --upgrade pip
sudo -u "$USER_NAME" "$APP/.venv/bin/pip" install --quiet flask pillow python-escpos pycups

echo "==> CUPS config: enable file:// device backend"
if ! grep -q '^FileDevice Yes' /etc/cups/cups-files.conf; then
  echo 'FileDevice Yes' >> /etc/cups/cups-files.conf
fi
cupsctl --share-printers --remote-any
systemctl enable --now cups avahi-daemon
systemctl restart cups

echo "==> CUPS backend python venv (root-owned)"
if [[ ! -x "$CUPS_VENV/bin/python" ]]; then
  python3 -m venv "$CUPS_VENV"
fi
"$CUPS_VENV/bin/pip" install --quiet --upgrade pip
"$CUPS_VENV/bin/pip" install --quiet python-escpos pillow

echo "==> install CUPS backend script"
install -m 755 -o root -g root "$APP/cups/photobooth-backend" /usr/lib/cups/backend/photobooth
systemctl restart cups
sleep 1

echo "==> CUPS queue"
if ! lpstat -p Photobooth >/dev/null 2>&1; then
  lpadmin -p Photobooth -E -v photobooth:/dev/usb/lp0 -m raw
  cupsenable Photobooth
  cupsaccept Photobooth
fi
lpadmin -p Photobooth -o media-default=80mm

echo "==> systemd units"
install -m 644 "$APP/systemd/photobooth-tunnel.service" /etc/systemd/system/photobooth-tunnel.service
sed "s|<UUID>|$UUID|" "$APP/systemd/photobooth.service" > /etc/systemd/system/photobooth.service
chmod 644 /etc/systemd/system/photobooth.service
systemctl daemon-reload
systemctl enable --now photobooth photobooth-tunnel

echo "==> restart in case unit files changed"
systemctl restart photobooth photobooth-tunnel
sleep 2
systemctl is-active photobooth photobooth-tunnel

cat <<EOF

=========================================================================
provisioning complete

Magic-link URL (static; comes from /etc/photobooth/auth_uuid which was
copied in by pi/bootstrap.sh):

   https://photobooth.ulyssepence.com/$UUID

Tunnel pubkey (already authorized in king's k3s photobooth ConfigMap):

$(cat "$ETC_DIR/tunnel_key.pub")

Reverse-tunnel target is hardcoded to ${KING_IP}:${TUNNEL_PORT}. If king's
IP changes, edit pi/systemd/photobooth-tunnel.service and re-run bootstrap.

=========================================================================
EOF
