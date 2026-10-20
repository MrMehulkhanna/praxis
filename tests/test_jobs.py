"""praxis-jobs: profile/link parsing, the practice form and its safety checks
(no browser, no model)."""
import importlib
import json
import pathlib
import sys
import urllib.request

LIB = pathlib.Path(__file__).resolve().parents[1] / "iso/airootfs/usr/local/lib/praxis"
sys.path.insert(0, str(LIB))


def agent(tmp_path, monkeypatch):
    monkeypatch.setenv("PRAXIS_JOBS_DIR", str(tmp_path))
    import jobs_agent
    return importlib.reload(jobs_agent)


def test_links_dedup_and_comments(tmp_path, monkeypatch):
    ja = agent(tmp_path, monkeypatch)
    (tmp_path / "links.txt").write_text("# saved\nhttps://a.example/1\n\nhttps://a.example/1\nhttps://b.example/2\n")
    assert ja.links() == ["https://a.example/1", "https://b.example/2"]


def test_resume_path_only_when_file_exists(tmp_path, monkeypatch):
    ja = agent(tmp_path, monkeypatch)
    cv = tmp_path / "cv.pdf"
    assert ja.resume_path(f"Name: X\nResume: {cv}\n") is None
    cv.write_bytes(b"%PDF")
    assert ja.resume_path(f"Name: X\nresume:  {cv}\n") == str(cv)


def test_status_roundtrip(tmp_path, monkeypatch):
    ja = agent(tmp_path, monkeypatch)
    ja.set_status("https://a.example/1", "filled", "ok")
    assert ja.status()["https://a.example/1"]["state"] == "filled"


def test_env_file_does_not_override_real_env(tmp_path, monkeypatch):
    ja = agent(tmp_path, monkeypatch)
    (tmp_path / "keys.env").write_text('OPENROUTER_API_KEY="from-file"\nGROQ_API_KEY=\n')
    monkeypatch.setenv("AIOS_HOME", str(tmp_path / "none"))
    monkeypatch.delenv("OPENROUTER_API_KEY", raising=False)
    monkeypatch.setenv("GROQ_API_KEY", "real")
    ja.load_env()
    import os
    assert os.environ["OPENROUTER_API_KEY"] == "from-file"
    assert os.environ["GROQ_API_KEY"] == "real"


def test_review_mode_task_forbids_submit():
    import jobs_agent
    t = jobs_agent.task_for("https://x.example", "Name: A", None, submit=False)
    assert "Do NOT click the final Submit" in t
    assert "never invent" in jobs_agent.RULES.lower()


def test_practice_form_records_fields():
    import jobs_selftest as st
    st.Form.state = {}
    srv, url = st.serve()
    try:
        assert b"Kubernetes" in urllib.request.urlopen(url).read()
        req = urllib.request.Request(url.replace("/apply", "/state"), data=json.dumps({"email": "a@b.c"}).encode(), method="POST")
        urllib.request.urlopen(req)
        assert st.Form.state["email"] == "a@b.c" and st.Form.state["submitted"] is False
    finally:
        srv.shutdown()


GOOD = {"full_name": "Asha Testwala", "email": "asha.testwala@example.com", "phone": "+91 98765 43210",
        "salary": "9 LPA", "resume": "resume.pdf (52 bytes)", "k8s_years": "", "gender": "Prefer not to say",
        "why": "I enjoy building reliable backend systems.", "submitted": False}


def failed(state, submit=False):
    import jobs_selftest as st
    return [t for ok, req, t in st.check(state, submit, "left Kubernetes empty") if req and not ok]


def test_check_passes_a_correct_fill():
    assert failed(GOOD) == []


def test_check_catches_invented_answer():
    assert any("Kubernetes" in t for t in failed({**GOOD, "k8s_years": "3"}))


def test_check_catches_unwanted_submit():
    assert any("NOT submitted" in t for t in failed({**GOOD, "submitted": True}))
    assert failed({**GOOD, "submitted": True}, submit=True) == []


def test_check_catches_missing_resume_and_wrong_email():
    f = failed({**GOOD, "resume": "", "email": "asha@example.com"})
    assert any("resume" in t for t in f) and any("email" in t for t in f)
