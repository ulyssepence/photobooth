import argparse
from pathlib import Path

import driver
import jobqueue
import server
import worker

ROOT = Path(__file__).parent


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--auth-uuid", required=True, help="secret token; visit /<token> to mint cookie")
    p.add_argument("--port", type=int, default=8080)
    p.add_argument("--driver", choices=["mock", "file", "usb"], default="mock")
    p.add_argument("--device", help="character device path for file driver (e.g. /dev/usb/lp0)")
    p.add_argument("--usb-vid", type=lambda s: int(s, 16), help="hex vendor id for usb driver")
    p.add_argument("--usb-pid", type=lambda s: int(s, 16), help="hex product id for usb driver")
    args = p.parse_args()

    queue = jobqueue.Queue(ROOT / "data" / "jobs.db")
    drv = driver.make(
        args.driver,
        mock_dir=ROOT / "output",
        device=args.device,
        usb_vid=args.usb_vid,
        usb_pid=args.usb_pid,
    )
    w = worker.Worker(queue, drv)
    w.start()
    app = server.make_app(queue, ROOT / "data" / "blobs", auth_uuid=args.auth_uuid)
    app.run(host="0.0.0.0", port=args.port)


if __name__ == "__main__":
    main()
