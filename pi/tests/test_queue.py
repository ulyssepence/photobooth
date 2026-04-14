import jobqueue


def test_enqueue_claim_complete(tmp_path):
    q = jobqueue.Queue(tmp_path / "jobs.db")
    jid = q.enqueue("http", "a.png", str(tmp_path / "a.png"))
    job = q.claim_next()
    assert job.id == jid
    assert job.status == "printing"
    assert q.claim_next() is None
    q.complete(jid)
    assert q.get(jid).status == "done"


def test_fail(tmp_path):
    q = jobqueue.Queue(tmp_path / "jobs.db")
    jid = q.enqueue("http", "a.png", str(tmp_path / "a.png"))
    q.claim_next()
    q.fail(jid, "boom")
    j = q.get(jid)
    assert j.status == "failed"
    assert j.error == "boom"


def test_persistence_recovers_printing(tmp_path):
    db = tmp_path / "jobs.db"
    q = jobqueue.Queue(db)
    jid = q.enqueue("http", "a.png", str(tmp_path / "a.png"))
    q.claim_next()  # marked printing
    q.close()

    q2 = jobqueue.Queue(db)
    # Recovery: previously-printing job is requeued.
    job = q2.claim_next()
    assert job.id == jid
    assert job.status == "printing"
