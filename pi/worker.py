import threading
import time
import traceback
from pathlib import Path

import driver as drv
import image as imageproc
import jobqueue


class Worker:
    def __init__(self, queue: jobqueue.Queue, driver: drv.Driver, poll_interval: float = 0.25):
        self.queue = queue
        self.driver = driver
        self.poll_interval = poll_interval
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=2)

    def _run(self) -> None:
        while not self._stop.is_set():
            job = self.queue.claim_next()
            if job is None:
                self._stop.wait(self.poll_interval)
                continue
            try:
                blob = Path(job.blob_path).read_bytes()
                img = imageproc.prepare(blob, width_mm=job.width_mm)
                self.driver.print_bitmap(job.id, img)
                self.queue.complete(job.id)
            except Exception:
                self.queue.fail(job.id, traceback.format_exc())
