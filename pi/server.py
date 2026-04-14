import hmac
import uuid as _uuid
from dataclasses import asdict
from pathlib import Path

from flask import Flask, abort, jsonify, make_response, redirect, request, send_from_directory

import jobqueue

WEB_DIR = Path(__file__).parent / "web"
COOKIE_NAME = "pb_auth"


def make_app(queue: jobqueue.Queue, blob_dir: Path, auth_uuid: str) -> Flask:
    app = Flask(__name__)
    blob_dir.mkdir(parents=True, exist_ok=True)

    def authed() -> bool:
        c = request.cookies.get(COOKIE_NAME, "")
        return hmac.compare_digest(c, auth_uuid)

    @app.before_request
    def gate():
        # Allow only:
        #   GET /<auth_uuid>  -> mints cookie, redirects to /
        #   /healthz          -> for tunnel health checks
        # Everything else requires the cookie. Unauthed = 404 (no oracle).
        path = request.path
        if path == "/healthz":
            return None
        if path == f"/{auth_uuid}":
            return None
        if not authed():
            abort(404)
        return None

    @app.get(f"/{auth_uuid}")
    def login():
        resp = make_response(redirect("/"))
        # 1 year, HttpOnly so JS can't read it; Secure since we're behind TLS at the ingress.
        resp.set_cookie(
            COOKIE_NAME, auth_uuid,
            max_age=365 * 24 * 3600,
            httponly=True, secure=True, samesite="Lax",
        )
        return resp

    @app.get("/healthz")
    def healthz():
        return {"ok": True}

    @app.get("/")
    def index():
        return send_from_directory(WEB_DIR, "index.html")

    @app.post("/print")
    def submit():
        f = request.files.get("image")
        if f is None:
            return {"error": "missing image field"}, 400
        try:
            width_mm = int(request.form.get("width_mm", "80"))
            count = max(1, min(20, int(request.form.get("count", "1"))))
        except ValueError:
            return {"error": "bad width_mm or count"}, 400
        if width_mm not in (58, 80):
            return {"error": "width_mm must be 58 or 80"}, 400

        # Stage once, enqueue N jobs that share the same blob.
        filename = f.filename or "upload.bin"
        blob_path = blob_dir / f"{_uuid.uuid4().hex}_{filename}"
        f.save(blob_path)
        job_ids = [
            queue.enqueue("http", filename=filename, blob_path=str(blob_path), width_mm=width_mm)
            for _ in range(count)
        ]
        return {"job_ids": job_ids}, 202

    @app.get("/jobs")
    def list_jobs():
        return jsonify([asdict(j) for j in queue.recent()])

    @app.get("/jobs/<int:job_id>")
    def get_job(job_id: int):
        job = queue.get(job_id)
        if job is None:
            return {"error": "not found"}, 404
        return asdict(job)

    return app
