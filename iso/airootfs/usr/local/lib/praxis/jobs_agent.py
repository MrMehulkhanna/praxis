"""praxis-jobs agent — fills job application forms with browser-use.

Run through `praxis-jobs run` (it provides the virtualenv). Reads the
applicant profile and the saved job links from ~/.config/praxis/jobs/, opens
each link in a dedicated Chrome profile (logins to LinkedIn, Workday … stay),
and lets the model fill the form from the profile only.

By default it stops before the final submit and waits for you to check the
form; with --submit it submits by itself.

Which brain (all free unless you choose otherwise), first match wins:
  PRAXIS_JOBS_MODEL=provider:model    explicit, e.g. openrouter:google/gemma-4-31b-it:free
  GOOGLE_API_KEY                      Gemini (free tier)
  OPENROUTER_API_KEY                  OpenRouter free models
  GROQ_API_KEY                        Groq (free tier)
  otherwise                           the local model through the Praxis gateway
Keys are read from ~/aios/config/aios.env (where Settings › AI keeps them)
and ~/.config/praxis/jobs/keys.env.
"""
import argparse
import asyncio
import json
import os
import pathlib
import re
import shutil
import sys
import time

HOME = pathlib.Path.home()
JOBS = pathlib.Path(os.environ.get("PRAXIS_JOBS_DIR", HOME / ".config/praxis/jobs"))
PROFILE = JOBS / "profile.md"
LINKS = JOBS / "links.txt"
STATUS = JOBS / "status.json"
CHROME_PROFILE = JOBS / "chrome-profile"
LOGS = JOBS / "logs"

OPENROUTER_FREE = ["nvidia/nemotron-3.5-super-vl:free", "google/gemma-4-31b-it:free"]


# ── state ───────────────────────────────────────────────────────────────
def load_env():
    for f in (pathlib.Path(os.environ.get("AIOS_HOME", HOME / "aios")) / "config/aios.env", JOBS / "keys.env"):
        if not f.is_file():
            continue
        for line in f.read_text().splitlines():
            m = re.match(r"\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$", line)
            if m and m.group(2).strip().strip("\"'") and m.group(1) not in os.environ:
                os.environ[m.group(1)] = m.group(2).strip().strip("\"'")


def links():
    if not LINKS.is_file():
        return []
    out = []
    for line in LINKS.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and line not in out:
            out.append(line)
    return out


def status():
    try:
        return json.loads(STATUS.read_text())
    except (OSError, ValueError):
        return {}


def set_status(url, state, note=""):
    s = status()
    s[url] = {"state": state, "note": note[:2000], "time": time.strftime("%Y-%m-%d %H:%M")}
    STATUS.write_text(json.dumps(s, indent=1))


def resume_path(profile_text):
    m = re.search(r"^\s*(?:resume|cv)\s*(?:file|path)?\s*:\s*(.+)$", profile_text, re.I | re.M)
    if not m:
        return None
    p = pathlib.Path(m.group(1).strip().strip("\"'")).expanduser()
    return str(p) if p.is_file() else None


# ── model ───────────────────────────────────────────────────────────────
def pick_llm():
    """→ (llm, fallback_llm, label, vision)"""
    from browser_use import ChatGoogle, ChatGroq, ChatOpenAI, ChatOpenRouter

    def openrouter(model):
        return ChatOpenRouter(model=model, api_key=os.environ["OPENROUTER_API_KEY"], temperature=0.2)

    want = os.environ.get("PRAXIS_JOBS_MODEL", "")
    if want:
        prov, _, model = want.partition(":")
        if prov == "google":
            return ChatGoogle(model=model, api_key=os.environ.get("GOOGLE_API_KEY")), None, want, True
        if prov == "openrouter":
            return openrouter(model), None, want, True
        if prov == "groq":
            return ChatGroq(model=model, api_key=os.environ.get("GROQ_API_KEY")), None, want, True
        if prov == "openai":       # any OpenAI-compatible server: PRAXIS_JOBS_BASE_URL
            return (ChatOpenAI(model=model, base_url=os.environ.get("PRAXIS_JOBS_BASE_URL"),
                               api_key=os.environ.get("OPENAI_API_KEY", "none")),
                    None, want, os.environ.get("PRAXIS_JOBS_VISION") == "1")
        sys.exit(f"praxis-jobs: unknown provider in PRAXIS_JOBS_MODEL={want} (google|openrouter|groq|openai)")
    if os.environ.get("GOOGLE_API_KEY"):
        return ChatGoogle(model="gemini-flash-latest", api_key=os.environ["GOOGLE_API_KEY"]), None, "Gemini Flash (free tier)", True
    if os.environ.get("OPENROUTER_API_KEY"):
        return openrouter(OPENROUTER_FREE[0]), openrouter(OPENROUTER_FREE[1]), f"OpenRouter {OPENROUTER_FREE[0]}", True
    if os.environ.get("GROQ_API_KEY"):
        return (ChatGroq(model="meta-llama/llama-4-scout-17b-16e-instruct", api_key=os.environ["GROQ_API_KEY"]),
                None, "Groq Llama 4 Scout (free tier)", True)
    # local: tested on a 6 GB GPU (Qwen3 8B, 8k context) it fails — every step
    # sends more than 8k tokens. Kept for big-GPU machines.
    # The Praxis gateway loads/unloads the model and applies the budget gate;
    # it doesn't forward response_format, so ask for the JSON in the prompt instead
    return (ChatOpenAI(model="auto", base_url="http://127.0.0.1:8778/v1", api_key="praxis",
                       add_schema_to_system_prompt=True, dont_force_structured_output=True),
            None, "local model (slow and less reliable — add a free key for better results)", False)


# ── the task ────────────────────────────────────────────────────────────
RULES = """You fill in job application forms for the applicant described below.
Rules:
- Use ONLY facts from the applicant profile. Never invent experience, dates,
  degrees, employers, numbers or answers. If a required question isn't covered
  by the profile, leave it empty and list it in your final message.
- Upload the resume file when there is a resume / CV upload field.
- If the page asks to sign in or create an account and you are not signed in,
  stop and say so — do not create accounts or guess passwords.
- Don't solve CAPTCHAs; stop and report one if it blocks you.
- Prefer "Apply" / "Easy Apply" / "Apply now" buttons to reach the form.
  Go through every page of a multi-page form.
- Don't change the applicant's saved account settings and don't subscribe to newsletters.
"""


def task_for(url, profile_text, resume, submit):
    finish = ("When every field is filled, click the final Submit / Send application button, then confirm "
              "the confirmation page or message appeared." if submit else
              "When every field is filled, STOP. Do NOT click the final Submit / Send application button — "
              "the applicant will review and submit it themselves.")
    return (f"Open {url} and fill in the job application.\n\n{finish}\n\n"
            f"Resume file: {resume or 'none given — skip upload fields and mention them'}\n\n"
            "Your final message: the job title and company, what you filled in, every question you left "
            "empty and why, and whether it was submitted.\n\n"
            f"=== APPLICANT PROFILE ===\n{profile_text}\n=== END PROFILE ===")


async def apply_one(url, profile_text, resume, submit, max_steps, keep_open):
    from browser_use import Agent, Browser

    llm, fallback, label, vision = pick_llm()
    chrome = shutil.which("google-chrome-stable") or shutil.which("google-chrome") or shutil.which("chromium")
    browser = Browser(executable_path=chrome, user_data_dir=str(CHROME_PROFILE), headless=False,
                      keep_alive=keep_open, downloads_path=str(JOBS / "downloads"))
    print(f"\n▶ {url}\n  brain: {label}")
    agent = Agent(task=task_for(url, profile_text, resume, submit), llm=llm, fallback_llm=fallback,
                  browser=browser, extend_system_message=RULES, use_vision=vision,
                  available_file_paths=[resume] if resume else None,
                  save_conversation_path=str(LOGS / re.sub(r"\W+", "_", url)[:80]))
    history = await agent.run(max_steps=max_steps)
    return browser, history


async def cmd_run(a):
    profile_text = PROFILE.read_text() if PROFILE.is_file() else ""
    if not profile_text.strip() or "Your Name" in profile_text:
        sys.exit("praxis-jobs: fill in your profile first — praxis-jobs profile")
    resume = resume_path(profile_text)
    if not resume:
        print("praxis-jobs: no resume found (add a line `Resume: /path/to/cv.pdf` to the profile) — continuing without", file=sys.stderr)
    st = status()
    todo = [a.url] if a.url else [u for u in links() if st.get(u, {}).get("state") not in ("submitted", "skipped")]
    if a.limit:
        todo = todo[:a.limit]
    if not todo:
        print("Nothing to do — add links with: praxis-jobs add URL …")
        return
    LOGS.mkdir(parents=True, exist_ok=True)
    for i, url in enumerate(todo, 1):
        print(f"\n[{i}/{len(todo)}]", end="")
        try:
            browser, h = await apply_one(url, profile_text, resume, a.submit, a.max_steps, keep_open=not a.submit)
        except Exception as e:      # one bad site shouldn't end the run
            set_status(url, "failed", repr(e))
            print(f"  ✗ {e}")
            continue
        result = h.final_result() or "(no summary)"
        print("\n" + result.strip())
        if a.submit:
            set_status(url, "submitted" if h.is_successful() else "failed", result)
            continue
        set_status(url, "filled", result)
        try:
            ans = (await asyncio.to_thread(input, "\nCheck the form in the browser. Did you submit it? [y]es / [s]kip this job / Enter = later: ")).strip().lower()
        except EOFError:
            ans = ""
        if ans.startswith("y"):
            set_status(url, "submitted", result)
        elif ans.startswith("s"):
            set_status(url, "skipped", result)
        try:
            await browser.kill()
        except Exception:
            pass


def main():
    load_env()
    os.environ.setdefault("ANONYMIZED_TELEMETRY", "false")
    os.environ.setdefault("BROWSER_USE_SETUP_LOGGING", "true")
    p = argparse.ArgumentParser(prog="praxis-jobs run")
    p.add_argument("--submit", action="store_true", help="submit by itself instead of stopping for review")
    p.add_argument("--limit", type=int, default=0, help="at most N jobs this time")
    p.add_argument("--url", help="just this link")
    p.add_argument("--max-steps", type=int, default=60)
    a = p.parse_args()
    JOBS.mkdir(parents=True, exist_ok=True)
    try:
        asyncio.run(cmd_run(a))
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
