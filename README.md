- [`macOS/`](macOS/) — SwiftUI app. Camera capture, Metal filters, prints locally via CUPS.
- [`pi/`](pi/) — Raspberry Pi 3B+ print service. Flask + SQLite queue + ESC/POS driver for a Rongta RP326 thermal printer. Exposed over HTTPS via a reverse SSH tunnel so phones can hit it from Safari. See [`pi/README.md`](pi/README.md).

## macOS app

```sh
cd macOS
swift run
```

Requires macOS 14+. Shaders are Metal; filters live in `Sources/Shaders/Kernels.ci.metal`.

## Pi service

See [`pi/README.md`](pi/README.md) for dev quickstart, deployment, and the tunnel/auth model.
