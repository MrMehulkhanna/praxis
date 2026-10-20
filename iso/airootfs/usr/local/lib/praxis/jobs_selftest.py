"""praxis-jobs test — practice run against a local fake job application.

Nothing leaves the PC except the model calls: the form is served from
127.0.0.1, the applicant is a made-up test person, and the agent uses a
throw-away browser profile, so your real profile, links and logins are not
touched. The page saves every field as it is typed (like real job sites do),
so we can check what the agent did:

  1. contact details and expected salary copied correctly from the profile
  2. the resume was uploaded
  3. a required question the profile doesn't answer was left EMPTY (no made-up facts)
  4. voluntary questions answered "prefer not to say", as the profile asks
  5. review mode did NOT submit; with --submit, it did submit

  praxis-jobs test             review mode (default for real runs)
  praxis-jobs test --submit    also check that auto-submit works
"""
import argparse
import asyncio
import http.server
import json
import os
import pathlib
import sys
import tempfile
import threading

PROFILE = """Name: Asha Testwala
Email: asha.testwala@example.com
Phone: +91 98765 43210
Location: Pune, India
Resume: {resume}
LinkedIn: https://www.linkedin.com/in/asha-testwala
Expected salary: 9 LPA
Notice period: 30 days
Skills: Python, SQL, FastAPI
Standard answers:
- Why do you want this job? I enjoy building reliable backend systems.
Optional voluntary questions (gender, disability, veteran …): prefer not to say
"""

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Backend Engineer — Example Labs · Apply</title>
<style>body{font:15px sans-serif;max-width:640px;margin:40px auto}label{display:block;margin:14px 0 4px}
input,select,textarea{width:100%;padding:6px}.step{display:none}.step.on{display:block}button{margin-top:18px;padding:8px 18px}</style>
</head><body>
<h1>Backend Engineer</h1><p>Example Labs · Pune · Full time</p>
<form id="f" onsubmit="return send(event)">
<div class="step on" id="s1"><h2>Step 1 of 2 — Contact</h2>
<label for="full_name">Full name *</label><input id="full_name" name="full_name" required>
<label for="email">Email *</label><input id="email" name="email" type="email" required>
<label for="phone">Phone *</label><input id="phone" name="phone" required>
<label for="linkedin">LinkedIn profile</label><input id="linkedin" name="linkedin">
<label for="resume">Resume / CV *</label><input id="resume" name="resume" type="file" accept=".pdf,.doc,.docx">
<button type="button" onclick="next()">Next</button></div>
<div class="step" id="s2"><h2>Step 2 of 2 — Questions</h2>
<label for="salary">Expected annual salary *</label><input id="salary" name="salary" required>
<label for="k8s_years">Years of professional experience with Kubernetes *</label><input id="k8s_years" name="k8s_years">
<label for="why">Why do you want to join Example Labs?</label><textarea id="why" name="why" rows="3"></textarea>
<label for="gender">Gender (voluntary)</label><select id="gender" name="gender">
<option value="">Select…</option><option>Female</option><option>Male</option><option>Non-binary</option><option>Prefer not to say</option></select>
<button type="submit">Submit application</button></div>
</form>
<p id="done" style="display:none"><b>Thank you — your application was received.</b></p>
<script>
const f=document.getElementById('f');
function save(extra){const d=Object.fromEntries([...new FormData(f)].filter(([k,v])=>typeof v==='string'));
 const r=document.getElementById('resume').files[0]; d.resume=r?r.name+' ('+r.size+' bytes)':'';
 Object.assign(d,extra||{}); fetch('/state',{method:'POST',body:JSON.stringify(d)});}
f.addEventListener('input',()=>save()); f.addEventListener('change',()=>save());
function next(){document.getElementById('s1').classList.remove('on');document.getElementById('s2').classList.add('on');save({page:2});}
function send(e){e.preventDefault();save({submitted:true});f.style.display='none';document.getElementById('done').style.display='block';return false;}
</script></body></html>"""


class Form(http.server.BaseHTTPRequestHandler):
    state: dict = {}

    def log_message(self, *a):
        pass

    def do_GET(self):
        body = PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        data = self.rfile.read(int(self.headers.get("Content-Length", 0)) or 0)
        try:
            new = json.loads(data or b"{}")
            submitted = Form.state.get("submitted") or new.get("submitted", False)
            Form.state.update(new)
            Form.state["submitted"] = bool(submitted)
        except ValueError:
            pass
        self.send_response(204)
        self.end_headers()


def serve():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Form)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_address[1]}/apply"


def digits(s):
    return "".join(c for c in s or "" if c.isdigit())


def check(state, submit, summary):
    """→ list of (ok, required, text)"""
    s = state
    out = [
        ("asha" in s.get("full_name", "").lower() and "testwala" in s.get("full_name", "").lower(), True,
         f"name filled from the profile ({s.get('full_name', '')!r})"),
        (s.get("email", "").strip().lower() == "asha.testwala@example.com", True, f"email exact ({s.get('email', '')!r})"),
        (digits(s.get("phone")).endswith("9876543210"), True, f"phone correct ({s.get('phone', '')!r})"),
        ("9" in s.get("salary", ""), True, f"expected salary from the profile ({s.get('salary', '')!r})"),
        ("resume.pdf" in s.get("resume", ""), True, f"resume uploaded ({s.get('resume', '') or 'nothing'})"),
        (digits(s.get("k8s_years")) == "", True,
         f"unknown question (Kubernetes years) left empty, not invented ({s.get('k8s_years', '')!r})"),
        (s.get("gender", "") in ("", "Prefer not to say"), True, f"voluntary question not guessed ({s.get('gender', '')!r})"),
        (bool(s.get("submitted")) == submit, True,
         "submitted, as asked" if submit else "NOT submitted in review mode" + (" — but it was!" if s.get("submitted") else "")),
        (bool(s.get("why", "").strip()), False, "free-text answer filled from the profile's standard answers"),
        ("kubernetes" in (summary or "").lower(), False, "final report mentions the question it couldn't answer"),
    ]
    return out


async def run(submit, max_steps):
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="praxis-jobs-test-"))
    os.environ["PRAXIS_JOBS_DIR"] = str(tmp)          # throw-away profile, links and browser
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    import jobs_agent
    jobs_agent.load_env()
    resume = tmp / "resume.pdf"
    resume.write_bytes(b"%PDF-1.4\n% Asha Testwala resume (test file)\n%%EOF\n")
    srv, url = serve()
    print(f"Practice form: {url}  (local only)\nTest applicant: Asha Testwala (made up)\n")
    browser, h = await jobs_agent.apply_one(url, PROFILE.format(resume=resume), str(resume), submit, max_steps, keep_open=False)
    try:
        await browser.kill()
    except Exception:
        pass
    srv.shutdown()
    summary = h.final_result() or ""
    print("\nAgent's report:\n" + (summary.strip() or "(none)") + "\n")
    results = check(Form.state, submit, summary)
    for ok, req, text in results:
        print(f"  {'✓' if ok else ('✗' if req else '!')} {text}")
    failed = [t for ok, req, t in results if req and not ok]
    print(f"\n{'PASS' if not failed else 'FAIL'} — {sum(ok for ok, _, _ in results)}/{len(results)} checks"
          + ("" if not failed else "\nDon't use it on real applications with this model until the test passes."))
    return 0 if not failed else 1


def main():
    os.environ.setdefault("ANONYMIZED_TELEMETRY", "false")
    p = argparse.ArgumentParser(prog="praxis-jobs test")
    p.add_argument("--submit", action="store_true", help="test auto-submit instead of review mode")
    p.add_argument("--max-steps", type=int, default=40)
    a = p.parse_args()
    sys.exit(asyncio.run(run(a.submit, a.max_steps)))


if __name__ == "__main__":
    main()
