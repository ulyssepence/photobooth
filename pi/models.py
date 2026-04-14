from dataclasses import dataclass
from typing import Literal, Optional

JobStatus = Literal["queued", "printing", "done", "failed"]
JobSource = Literal["ipp", "http"]


@dataclass
class Job:
    id: int
    created_at: float
    status: JobStatus
    source: JobSource
    filename: str
    blob_path: str
    width_mm: int = 80
    error: Optional[str] = None
    started_at: Optional[float] = None
    finished_at: Optional[float] = None
