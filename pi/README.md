# photobooth-pi

LAN print service for the photobooth Pi. Accepts image uploads over HTTP, queues them in SQLite, dithers to 384px wide 1-bit, and pushes to an ESC/POS thermal printer (Rongta RP326). Develop on Mac against `MockDriver`; deploy to a Raspberry Pi 3B+ for real printing.

## Dev quickstart (Mac, no printer)

```sh
cd pi
uv sync
uv run pytest
PHOTOBOOTH_DRIVER=mock uv run python app.py --auth-uuid dev-token
# in another shell:
curl -c jar.txt http://localhost:8080/dev-token   # mint cookie
curl -b jar.txt -F image=@../docs/sample.jpg http://localhost:8080/print
curl -b jar.txt http://localhost:8080/jobs
```

In a browser, just visit `http://localhost:8080/dev-token` once and you're in.

`MockDriver` writes the dithered output to `pi/output/<job_id>.png` so you can eyeball the result.

## Env vars

- `PHOTOBOOTH_DRIVER`: `mock` (default) or `usb`
- `PHOTOBOOTH_USB_VID` / `PHOTOBOOTH_USB_PID`: hex USB IDs (only when `usb`)
- `PHOTOBOOTH_PORT`: defaults to 8080

## Pi deployment (later, when hardware arrives)

1. Flash Raspberry Pi OS Lite via Pi Imager. In Imager's advanced options preconfigure: hostname `photobooth`, SSH on, WiFi creds, user. SSH in via `ssh pi@photobooth.local` (mDNS).
2. `sudo apt install -y python3 python3-venv libusb-1.0-0 cups avahi-daemon`
3. `git clone <this repo>` and `pip install -e pi/` (or use `uv`).
4. Find the Rongta USB IDs with `lsusb`, set `PHOTOBOOTH_USB_VID` / `PHOTOBOOTH_USB_PID`, `PHOTOBOOTH_DRIVER=usb`.
5. Add a `systemd` unit that runs `python app.py` on boot, port 80.

### Rotating the auth UUID

```sh
ssh photobooth@photobooth.local
uuidgen | tr -d '\n' | sudo tee /etc/photobooth/auth_uuid
sudo bash /home/photobooth/photobooth/pi/provision.sh   # idempotent; re-templates the systemd unit
```

The script reads `/etc/photobooth/auth_uuid`, sed-substitutes it into `/etc/systemd/system/photobooth.service`, and restarts `photobooth.service`. The old magic link instantly 404s; share the new one printed at the end of the script.

### Changing the CUPS default paper width

```sh
ssh photobooth@photobooth.local sudo lpadmin -p Photobooth -o media-default=80mm   # or 58mm
```

Per-job override from any client: `lp -o media=80mm file.pdf`. Only `58mm` and `80mm` are recognized; the backend ignores anything else and falls back to 58mm.

### Re-imaging the Pi

`pi/provision.sh` is the source of truth for the Pi-side environment. To rebuild from a wiped SD card, follow the bootstrap block at the top of that script. After it finishes, the script prints the freshly-generated tunnel pubkey and the auth UUID. **Both rotate on a wipe** (the script only preserves them across re-runs over an existing install). You must:

1. Replace the `authorized_keys` value in `~/Source/ultros/k3s/photobooth.yaml` with the new pubkey, then `kubectl apply -f photobooth.yaml` from king.
2. Update any QR codes / shared magic links to use the new UUID — the old one is dead.

If you wipe only `/etc/photobooth/` and leave the rest of the install intact, the same applies: a new UUID is minted and old links 404.

### Reverse tunnel to king (HTTPS via photobooth.ulyssepence.com)

iOS Safari requires a secure context for `getUserMedia`, so the Pi must be reached over HTTPS. We don't terminate TLS on the Pi — instead the Pi opens an outbound SSH reverse tunnel to a sshd pod running in king's k3s, and traefik fronts that pod with the existing Cloudflare origin cert.

**One-time setup:**

1. **Generate a Pi-side tunnel keypair** *on the Pi* (never copy the private half off it):
   ```sh
   sudo mkdir -p /etc/photobooth
   sudo ssh-keygen -t ed25519 -N "" -f /etc/photobooth/tunnel_key -C photobooth-tunnel
   sudo chown photobooth:photobooth /etc/photobooth/tunnel_key*
   sudo cat /etc/photobooth/tunnel_key.pub
   ```
2. **Paste the pubkey** into `~/Source/ultros/k3s/photobooth.yaml` under the ConfigMap's `authorized_keys` field, then `kubectl apply -f photobooth.yaml`.
3. **Point DNS** `photobooth.ulyssepence.com` at king (A record, proxied through Cloudflare like the other ulyssepence.com subdomains).
4. **Mint the access UUID** (do this once on the Pi, never commit it):
   ```sh
   uuidgen | tr -d '\n' | sudo tee /etc/photobooth/auth_uuid
   ```
5. **Edit `systemd/photobooth.service`** to substitute `<UUID>` with the contents of `/etc/photobooth/auth_uuid`, then install both unit files:
   ```sh
   sudo cp systemd/photobooth.service systemd/photobooth-tunnel.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now photobooth photobooth-tunnel
   ```
6. **Share the magic link**: `https://photobooth.ulyssepence.com/<UUID>`. Encode as a QR code and tape it to the printer. One scan sets a year-long cookie; subsequent visits go straight to `/`. Anyone without the cookie gets a 404 with no oracle.

**Auth model**: single shared UUID, passed to `app.py` via `--auth-uuid` (CLI arg, never an env var). `GET /<uuid>` mints `pb_auth=<uuid>` cookie; everything else 404s without it. `hmac.compare_digest` for constant-time check. `/healthz` is the only other public route (used by the tunnel).

**Why this shape**: chisel/frp/inlets all expose dashboards or use shared-secret auth — we want pubkey-only, matching the rest of king's SSH posture. Plain `autossh` over a sshd pod gets us there with one moving part on the Pi.

### CUPS / AirPrint (deferred)

Goal: have macOS/iOS see `photobooth.local` as an AirPrint printer with no app install. Two pieces:

- A CUPS queue backed by an ESC/POS filter so generic print jobs get rasterized → dithered → ESC/POS. Candidate shims: `cups-genericraster-escpos`, the various `rastertoescpos` filters bundled with thermal-printer profiles. Pick when real hardware is on the desk; spec leaves this open.
- `avahi-daemon` advertising the CUPS queue as IPP/AirPrint.

The Flask service in this repo is the integration we exercise day-to-day; CUPS is a *separate* path into the same printer. Both can coexist.

## Layout

- `app.py` — entrypoint, wires queue + worker + flask
- `models.py` — `Job` dataclass + status literals
- `jobqueue.py` — SQLite-backed queue
- `image.py` — luminance grayscale → resize 384w → Floyd–Steinberg
- `driver.py` — `Driver` protocol, `MockDriver`, `EscposDriver`
- `worker.py` — background thread that drains the queue
- `server.py` — Flask routes (`POST /print`, `GET /jobs`, `GET /jobs/<id>`, `GET /healthz`)
- `tests/` — pytest, all green against `MockDriver`

## Notes

- `models.py` and `jobqueue.py` are deliberately not named `types.py`/`queue.py` because those would shadow stdlib modules at the top of `sys.path`.
- The queue recovers `printing` jobs back to `queued` on startup, so a crash mid-print just retries.
