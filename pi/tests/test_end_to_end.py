import time
from io import BytesIO

from PIL import Image

import driver
import jobqueue
import server
import worker


def _png_bytes():
    img = Image.new("RGB", (600, 300), (200, 100, 50))
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def test_post_print_runs_through_worker(tmp_path):
    q = jobqueue.Queue(tmp_path / "jobs.db")
    drv = driver.MockDriver(tmp_path / "out")
    w = worker.Worker(q, drv, poll_interval=0.01)
    w.start()
    try:
        uuid = "test-uuid-1234"
        app = server.make_app(q, tmp_path / "blobs", auth_uuid=uuid)
        client = app.test_client()

        # Unauthed = 404 (no oracle).
        assert client.get("/").status_code == 404
        assert client.post("/print", data={"image": (BytesIO(_png_bytes()), "x.png")}).status_code == 404

        # Mint cookie via /<uuid>.
        r = client.get(f"/{uuid}")
        assert r.status_code == 302
        assert client.get("/").status_code == 200

        resp = client.post("/print", data={"image": (BytesIO(_png_bytes()), "hi.png"), "width_mm": "80", "count": "2"})
        assert resp.status_code == 202
        ids = resp.get_json()["job_ids"]
        assert len(ids) == 2
        jid = ids[-1]

        deadline = time.time() + 3
        while time.time() < deadline:
            j = q.get(jid)
            if j.status in ("done", "failed"):
                break
            time.sleep(0.02)

        j = q.get(jid)
        assert j.status == "done", j.error
        assert (tmp_path / "out" / f"{jid:06d}.png").exists()
    finally:
        w.stop()
