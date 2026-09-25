#!/usr/bin/env python3
"""
desk — Mehul's engineering desk. A small, local, honest productivity tracker.

Modular by design: skills, DSA, career, sessions and today's plan are separate
concerns sharing one SQLite file (~/.local/share/desk/desk.db). No cloud, no
telemetry, no invented statistics — every number comes from data you recorded.

Daily verbs (also installed as standalone commands):
  start-day        set today's outcome + priorities, show first action
  what-now         the single next thing to do, and why
  im-stuck         classify what kind of stuck you are, route to the right tool
  end-day          honest recap from recorded sessions + task completion
  start-study T    begin a focus session on topic T   (alias: desk study start)
  end-study        end the current focus session

Trackers:
  desk task add "..." [-p high|med|low] [-t MIN]   ·  task done N  ·  task ls
  desk skill add NAME [-c cat] [-l level] [-g goal] ·  skill ls  ·  skill set NAME field=val
  desk dsa add "NAME" [-p pattern] [-d easy|med|hard] [-u url]  ·  dsa ls  ·  dsa solved N [--hint|--solution]
  desk career add "COMPANY" "ROLE" [-u url] [-r resume]  ·  career ls  ·  career status N STAGE
  desk log                              recent sessions
  desk (no args)                        today's command center

All state is yours and plain: `sqlite3 ~/.local/share/desk/desk.db`.
"""
import argparse, os, sqlite3, sys, time, textwrap, datetime, json, subprocess, shutil

DB = os.path.expanduser("~/.local/share/desk/desk.db")
C = dict(d="\033[2m", b="\033[1m", r="\033[31m", g="\033[32m", y="\033[33m",
         c="\033[36m", m="\033[35m", blue="\033[34m", rst="\033[0m")
if not sys.stdout.isatty():
    C = {k: "" for k in C}

def color(s, k): return f"{C[k]}{s}{C['rst']}"
def today(): return datetime.date.today().isoformat()
def now(): return time.time()

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY, day TEXT, text TEXT, priority TEXT DEFAULT 'med',
  est_min INTEGER DEFAULT 0, done INTEGER DEFAULT 0, created_at REAL);
CREATE TABLE IF NOT EXISTS skills (
  id INTEGER PRIMARY KEY, name TEXT UNIQUE, category TEXT DEFAULT 'general',
  level TEXT DEFAULT 'beginner', goal TEXT DEFAULT 'interview-ready',
  current_topic TEXT DEFAULT '', next_action TEXT DEFAULT '',
  last_practiced TEXT, notes TEXT DEFAULT '', created_at REAL);
CREATE TABLE IF NOT EXISTS dsa (
  id INTEGER PRIMARY KEY, name TEXT, url TEXT DEFAULT '', pattern TEXT DEFAULT '',
  difficulty TEXT DEFAULT 'med', independent INTEGER DEFAULT 0,
  needed_hint INTEGER DEFAULT 0, needed_solution INTEGER DEFAULT 0,
  mistake TEXT DEFAULT '', status TEXT DEFAULT 'todo', revisit TEXT DEFAULT '',
  solved_at REAL, created_at REAL);
CREATE TABLE IF NOT EXISTS career (
  id INTEGER PRIMARY KEY, company TEXT, role TEXT, url TEXT DEFAULT '',
  applied TEXT DEFAULT '', resume TEXT DEFAULT '', status TEXT DEFAULT 'interested',
  referral TEXT DEFAULT '', followup TEXT DEFAULT '', stage TEXT DEFAULT '',
  notes TEXT DEFAULT '', created_at REAL);
CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY, kind TEXT DEFAULT 'study', topic TEXT DEFAULT '',
  started REAL, ended REAL, minutes REAL DEFAULT 0, note TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT);
"""

def db():
    c = sqlite3.connect(DB); c.row_factory = sqlite3.Row; c.executescript(SCHEMA); return c

def kv_get(c, k, default=None):
    r = c.execute("SELECT value FROM kv WHERE key=?", (k,)).fetchone()
    return json.loads(r["value"]) if r else default
def kv_set(c, k, v):
    c.execute("INSERT OR REPLACE INTO kv VALUES (?,?)", (k, json.dumps(v))); c.commit()

def ask(prompt, default=""):
    if not sys.stdin.isatty(): return default
    try:
        v = input(f"{C['c']}{prompt}{C['rst']}" + (f" {C['d']}[{default}]{C['rst']}" if default else "") + " ").strip()
        return v or default
    except (EOFError, KeyboardInterrupt): print(); return default

def fmt_min(m):
    m = int(round(m)); return f"{m//60}h {m%60}m" if m >= 60 else f"{m}m"

# ── sessions ────────────────────────────────────────────────────────────
def active_session(c):
    return c.execute("SELECT * FROM sessions WHERE ended IS NULL ORDER BY started DESC LIMIT 1").fetchone()

def start_study(args):
    c = db()
    if active_session(c):
        s = active_session(c); print(color(f"already in a session: {s['kind']} · {s['topic']} ({fmt_min((now()-s['started'])/60)})", "y")); return
    topic = " ".join(args.topic) if getattr(args, "topic", None) else ask("Topic?", "")
    kind = getattr(args, "kind", None) or "study"
    c.execute("INSERT INTO sessions (kind, topic, started) VALUES (?,?,?)", (kind, topic, now())); c.commit()
    print(color(f"▶ {kind} session started", "g") + f" · {topic or '(no topic)'}  " + color("— end-study when done", "d"))

def end_study(args):
    c = db(); s = active_session(c)
    if not s: print(color("no active session", "d")); return
    mins = (now() - s["started"]) / 60
    note = ask("One line — what did you get done?", "") if sys.stdin.isatty() else ""
    c.execute("UPDATE sessions SET ended=?, minutes=?, note=? WHERE id=?", (now(), mins, note, s["id"])); c.commit()
    if s["topic"]:
        c.execute("UPDATE skills SET last_practiced=? WHERE current_topic=? OR name=?", (today(), s["topic"], s["topic"])); c.commit()
    print(color(f"■ {fmt_min(mins)} on {s['topic'] or s['kind']}", "g"))

def today_minutes(c, day=None):
    day = day or today()
    rows = c.execute("SELECT kind, SUM(minutes) m FROM sessions WHERE ended IS NOT NULL AND date(started,'unixepoch','localtime')=? GROUP BY kind", (day,)).fetchall()
    return {r["kind"]: r["m"] for r in rows}

# ── tasks ───────────────────────────────────────────────────────────────
PRI = {"high": (C['r'], 0), "med": (C['y'], 1), "low": (C['d'], 2)}
def task_add(args):
    c = db(); text = " ".join(args.text)
    c.execute("INSERT INTO tasks (day, text, priority, est_min, created_at) VALUES (?,?,?,?,?)",
              (today(), text, args.priority, args.time or 0, now())); c.commit()
    print(color("+ ", "g") + text)
def task_done(args):
    c = db(); c.execute("UPDATE tasks SET done=1 WHERE id=?", (args.n,)); c.commit(); print(color("✓ done", "g"))
def task_ls(args):
    c = db(); rows = c.execute("SELECT * FROM tasks WHERE day=? ORDER BY done, CASE priority WHEN 'high' THEN 0 WHEN 'med' THEN 1 ELSE 2 END", (today(),)).fetchall()
    if not rows: print(color("no tasks today — `desk task add` or `start-day`", "d")); return
    for t in rows:
        box = color("✓", "g") if t["done"] else "○"
        pc = PRI.get(t["priority"], ("", 1))[0]
        est = color(f"  ~{t['est_min']}m", "d") if t["est_min"] else ""
        print(f"  {box} {color('#'+str(t['id']), 'd')} {pc}{t['text']}{C['rst']}{est}")

# ── skills ──────────────────────────────────────────────────────────────
def skill_add(args):
    c = db()
    try:
        c.execute("INSERT INTO skills (name, category, level, goal, created_at) VALUES (?,?,?,?,?)",
                  (args.name, args.category, args.level, args.goal, now())); c.commit()
        print(color(f"+ skill {args.name}", "g"))
    except sqlite3.IntegrityError:
        print(color(f"{args.name} already tracked — use `desk skill set`", "y"))
def skill_set(args):
    c = db()
    allowed = {"category", "level", "goal", "current_topic", "next_action", "notes"}
    changed = []
    for kv in args.fields:
        if "=" not in kv: continue
        k, v = kv.split("=", 1)
        if k in allowed:
            c.execute(f"UPDATE skills SET {k}=? WHERE name=?", (v, args.name)); changed.append(k)
    c.commit(); print(color(f"✓ {args.name}: {', '.join(changed) or 'no change'}", "g"))
def skill_ls(args):
    c = db(); rows = c.execute("SELECT * FROM skills ORDER BY category, name").fetchall()
    if not rows: print(color("no skills tracked — `desk skill add C++ -c dsa -g interview-ready`", "d")); return
    cat = None
    for s in rows:
        if s["category"] != cat: cat = s["category"]; print(color(f"\n{cat.upper()}", "m"))
        lp = s["last_practiced"] or "never"
        solved = c.execute("SELECT COUNT(*) n FROM dsa WHERE status='solved' AND pattern=?", (s["name"],)).fetchone()["n"]
        print(f"  {color(s['name'], 'b')}  {s['level']} → {s['goal']}")
        if s["current_topic"]: print(f"     now: {s['current_topic']}" + (f"  →  next: {color(s['next_action'], 'c')}" if s["next_action"] else ""))
        print(color(f"     last practiced {lp}", "d"))

# ── dsa ─────────────────────────────────────────────────────────────────
def dsa_add(args):
    c = db(); name = " ".join(args.name)
    c.execute("INSERT INTO dsa (name, url, pattern, difficulty, created_at) VALUES (?,?,?,?,?)",
              (name, args.url, args.pattern, args.difficulty, now())); c.commit()
    print(color(f"+ dsa {name}", "g"))
def dsa_solved(args):
    c = db()
    rev = (datetime.date.today() + datetime.timedelta(days=7 if (args.hint or args.solution) else 21)).isoformat()
    c.execute("UPDATE dsa SET status='solved', independent=?, needed_hint=?, needed_solution=?, mistake=?, revisit=?, solved_at=? WHERE id=?",
              (0 if (args.hint or args.solution) else 1, int(args.hint), int(args.solution), args.mistake or "", rev, now(), args.n)); c.commit()
    how = "with the solution" if args.solution else "with a hint" if args.hint else color("independently", "g")
    print(color("✓ solved ", "g") + how + color(f" · revisit {rev}", "d"))
def dsa_ls(args):
    c = db()
    q = "SELECT * FROM dsa"
    if args.due: q += f" WHERE status='solved' AND revisit<='{today()}'"
    q += " ORDER BY status, created_at DESC"
    rows = c.execute(q).fetchall()
    if not rows: print(color("no problems logged — `desk dsa add \"Two Sum\" -p hashing -d easy`", "d")); return
    stats = c.execute("SELECT COUNT(*) n, SUM(independent) ind, SUM(needed_solution) sol FROM dsa WHERE status='solved'").fetchone()
    for d in rows:
        mark = color("✓", "g") if d["status"] == "solved" else "○"
        flag = "" if d["status"] != "solved" else (color(" solo", "g") if d["independent"] else color(" hint", "y") if d["needed_hint"] else color(" sol", "r"))
        due = color(f"  ⟳ {d['revisit']}", "y") if d["status"] == "solved" and d["revisit"] and d["revisit"] <= today() else ""
        print(f"  {mark} {color('#'+str(d['id']),'d')} {d['name']}  {color(d['pattern'],'c')} {color(d['difficulty'],'d')}{flag}{due}")
    if stats["n"]: print(color(f"\n  {stats['n']} solved · {stats['ind'] or 0} independent · {stats['sol'] or 0} needed the solution", "d"))

# ── career ──────────────────────────────────────────────────────────────
def career_add(args):
    c = db()
    c.execute("INSERT INTO career (company, role, url, resume, applied, created_at) VALUES (?,?,?,?,?,?)",
              (args.company, args.role, args.url, args.resume, today() if args.applied else "", now())); c.commit()
    print(color(f"+ {args.company} · {args.role}", "g"))
def career_status(args):
    c = db(); c.execute("UPDATE career SET status=?, stage=? WHERE id=?", (args.stage, args.stage, args.n)); c.commit()
    print(color(f"✓ #{args.n} → {args.stage}", "g"))
def career_ls(args):
    c = db(); rows = c.execute("SELECT * FROM career ORDER BY created_at DESC").fetchall()
    if not rows: print(color("nothing tracked — `desk career add \"Company\" \"AI Engineer\" -u URL`", "d")); return
    sc = {"interested": "d", "applied": "c", "interviewing": "y", "offer": "g", "rejected": "r"}
    for j in rows:
        st = color(j["status"], sc.get(j["status"], "d"))
        print(f"  {color('#'+str(j['id']),'d')} {color(j['company'],'b')} · {j['role']}  [{st}]" + (color(f"  resume:{j['resume']}", "d") if j["resume"] else ""))
        if j["url"]: print(color(f"     {j['url']}", "d"))

def log_cmd(args):
    c = db(); rows = c.execute("SELECT * FROM sessions WHERE ended IS NOT NULL ORDER BY started DESC LIMIT 15").fetchall()
    if not rows: print(color("no sessions yet — `start-study <topic>`", "d")); return
    for s in rows:
        d = datetime.datetime.fromtimestamp(s["started"]).strftime("%m-%d %H:%M")
        print(f"  {color(d,'d')}  {color(fmt_min(s['minutes']),'b'):>18}  {s['kind']:6} {s['topic']}" + (color(f"  — {s['note']}", "d") if s["note"] else ""))

# ── daily commands ──────────────────────────────────────────────────────
def dashboard(args=None):
    c = db(); mins = today_minutes(c)
    total = sum(mins.values())
    outcome = kv_get(c, f"outcome:{today()}", "")
    tasks = c.execute("SELECT * FROM tasks WHERE day=? ORDER BY done, CASE priority WHEN 'high' THEN 0 WHEN 'med' THEN 1 ELSE 2 END", (today(),)).fetchall()
    done = sum(t["done"] for t in tasks)
    W = 46
    line = lambda s="": print("║ " + s + " " * max(0, W - _vlen(s)) + " ║")
    print(color("╔" + "═" * (W + 2) + "╗", "c"))
    title = "MEHUL · ENGINEERING DESK"
    print(color("║ " + title.center(W) + " ║", "c"))
    print(color("╠" + "═" * (W + 2) + "╣", "c"))
    line(color(datetime.date.today().strftime("%A %d %B"), "d"))
    if outcome: line(color("Outcome: ", "b") + outcome[:W-9])
    line()
    s = active_session(c)
    if s: line(color("▶ IN SESSION ", "g") + f"{s['topic'] or s['kind']} · {fmt_min((now()-s['started'])/60)}")
    if not tasks:
        line(color("no tasks — run start-day", "d"))
    pri_key = {"high": "r", "med": "y", "low": "d"}
    for t in tasks[:6]:
        if t["done"]:
            line("[" + color("✓", "g") + "] " + color(t["text"][:W-5], "d"))
        else:
            line("[ ] " + color(t["text"][:W-5], pri_key.get(t["priority"], "y")))
    line()
    parts = [f"{k} {fmt_min(v)}" for k, v in sorted(mins.items(), key=lambda x: -x[1])]
    line(color("Focus:  ", "b") + (color(fmt_min(total), "g") + "   " + " · ".join(parts) if total else color("nothing logged yet", "d")))
    if tasks: line(color("Tasks:  ", "b") + f"{done}/{len(tasks)} done")
    print(color("╚" + "═" * (W + 2) + "╝", "c"))
    nxt = _next_task(tasks)
    if nxt: print("  " + color("→ next:", "c") + f" {nxt['text']}" + (color(f"  (~{nxt['est_min']}m)", "d") if nxt["est_min"] else "") + color("   ·  what-now for why", "d"))

def _vlen(s):  # visible length ignoring ANSI
    import re; return len(re.sub(r"\033\[[0-9;]*m", "", s))

def _next_task(tasks):
    undone = [t for t in tasks if not t["done"]]
    if not undone: return None
    return sorted(undone, key=lambda t: {"high": 0, "med": 1, "low": 2}.get(t["priority"], 1))[0]

def start_day(args):
    c = db()
    if kv_get(c, f"outcome:{today()}") and not ask("Today already started — reset it? (y/N)", "n").lower().startswith("y"):
        return dashboard()
    print(color("\n  Good morning.\n", "b"))
    outcome = ask("Today's main outcome?", kv_get(c, f"outcome:{today()}", ""))
    kv_set(c, f"outcome:{today()}", outcome)
    c.execute("DELETE FROM tasks WHERE day=? AND done=0", (today(),)); c.commit()
    print(color("  Priority tasks (blank line to stop). Format: text | high/med/low | minutes", "d"))
    i = 1
    while True:
        raw = ask(f"  {i}.", "")
        if not raw: break
        parts = [p.strip() for p in raw.split("|")]
        text = parts[0]; pri = parts[1] if len(parts) > 1 and parts[1] in PRI else "med"
        est = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0
        c.execute("INSERT INTO tasks (day, text, priority, est_min, created_at) VALUES (?,?,?,?,?)", (today(), text, pri, est, now())); c.commit()
        i += 1
    print()
    dashboard()

def what_now(args):
    c = db()
    s = active_session(c)
    if s:
        print(color("You're already in a session:", "g") + f" {s['topic'] or s['kind']} · {fmt_min((now()-s['started'])/60)}")
        print(color("  Stay on it. `end-study` when the task is done.", "d")); return
    tasks = c.execute("SELECT * FROM tasks WHERE day=? AND done=0", (today(),)).fetchall()
    nxt = _next_task(tasks)
    due = c.execute("SELECT * FROM dsa WHERE status='solved' AND revisit<=? ORDER BY revisit LIMIT 1", (today(),)).fetchone()
    print()
    if not nxt and not due:
        print(color("  Nothing queued.", "y") + " Run " + color("start-day", "c") + " to set today's plan, or add a task.")
        weak = c.execute("SELECT * FROM skills WHERE next_action!='' ORDER BY last_practiced LIMIT 1").fetchone()
        if weak: print(color("  Longest untouched skill:", "d") + f" {weak['name']} → {weak['next_action']}")
        return
    print(color("  CURRENT PRIORITY", "b"))
    if nxt:
        print(f"\n  {color(nxt['text'], 'c')}")
        if nxt["est_min"]: print(color(f"  Estimated: {nxt['est_min']} min", "d"))
        print(color(f"  Why: highest-priority unfinished task for today.", "d"))
        print(f"\n  Action:  {color('start-study ' + nxt['text'][:30], 'g')}")
    if due:
        print(color(f"\n  Also due for spaced review: ", "y") + f"{due['name']} ({due['pattern']})  →  desk dsa ls --due")

STUCK_ROUTES = {
    "concept": ("A concept you don't fully understand", ["Open your notes: ~/Knowledge/<topic>",
        "Ask the local AI to explain it at your level:  ai ask \"explain X simply, then one example\"",
        "Write the concept in your own words in Knowledge/ — if you can't, that's the gap."]),
    "code": ("Code that won't work / a bug", ["ai \"<paste the error>\"  — the agent gathers context and explains",
        "Reproduce the smallest failing case", "Read the actual error top-to-bottom, not just the last line"]),
    "env": ("Environment / dependency / tooling", ["ai \"<what's broken>\"  — runs read-only diagnostics first",
        "ai doctor  (if it's the AI stack)", "Check versions & PATH:  which python3 · pip list"]),
    "logic": ("Logic / approach to a problem", ["Step away from the keyboard, write the algorithm in plain words",
        "For DSA: name the pattern first (hashing? two-pointer? DP?)", "desk dsa add it, then attempt before any hint"]),
    "plan": ("Don't know what to work on", ["what-now", "start-day to (re)set today's plan", "Look at your skills:  desk skill ls"]),
    "motivation": ("Low energy / can't start", ["Commit to 15 minutes only — start-study, timer runs",
        "Pick the smallest task:  desk task ls", "Momentum beats mood. One tiny action."]),
}
def im_stuck(args):
    print(color("\n  What kind of stuck?\n", "b"))
    keys = list(STUCK_ROUTES)
    for i, k in enumerate(keys, 1):
        print(f"  {color(str(i), 'c')}. {STUCK_ROUTES[k][0]}")
    ch = ask("\n  Pick a number", "")
    if not ch.isdigit() or not (1 <= int(ch) <= len(keys)):
        print(color("  (nothing picked)", "d")); return
    k = keys[int(ch) - 1]; label, steps = STUCK_ROUTES[k]
    print(color(f"\n  → {label}", "y"))
    for s in steps: print(f"     • {s}")
    print()

def end_day(args):
    c = db(); mins = today_minutes(c); total = sum(mins.values())
    tasks = c.execute("SELECT * FROM tasks WHERE day=?", (today(),)).fetchall()
    done = [t for t in tasks if t["done"]]; undone = [t for t in tasks if not t["done"]]
    dsa_today = c.execute("SELECT * FROM dsa WHERE date(solved_at,'unixepoch','localtime')=?", (today(),)).fetchall()
    sess = c.execute("SELECT * FROM sessions WHERE ended IS NOT NULL AND date(started,'unixepoch','localtime')=?", (today(),)).fetchall()
    print(color("\n  ── End of day ──", "b"))
    print(color(f"\n  Focused work: {fmt_min(total)}", "g") + (color(f"   ({' · '.join(f'{k} {fmt_min(v)}' for k,v in mins.items())})", "d") if mins else ""))
    print(f"  Sessions: {len(sess)}   Tasks: {color(str(len(done)),'g')}/{len(tasks)} done")
    if dsa_today:
        ind = sum(d["independent"] for d in dsa_today)
        print(f"  DSA: {len(dsa_today)} solved ({ind} independently)")
    if done:
        print(color("\n  Completed:", "g"))
        for t in done: print(f"     ✓ {t['text']}")
    if undone:
        print(color("\n  Carried over:", "y"))
        for t in undone: print(f"     ○ {t['text']}")
        if sys.stdin.isatty() and ask("\n  Carry these to tomorrow? (Y/n)", "y").lower() != "n":
            tm = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
            for t in undone: c.execute("UPDATE tasks SET day=? WHERE id=?", (tm, t["id"]))
            c.commit(); print(color("  moved to tomorrow", "d"))
    if total == 0 and not tasks:
        print(color("\n  No data recorded today. Nothing to report — that's honest, not a failure.", "d"))
    block = ask("\n  Any blocker for tomorrow? (optional)", "") if sys.stdin.isatty() else ""
    if block: kv_set(c, f"blocker:{today()}", block)
    print()

# ── argparse ────────────────────────────────────────────────────────────
def build_parser():
    p = argparse.ArgumentParser(prog="desk", description="Mehul's engineering desk", add_help=True)
    sub = p.add_subparsers(dest="cmd")
    for verb, fn in [("start-day", start_day), ("what-now", what_now), ("im-stuck", im_stuck),
                     ("end-day", end_day), ("end-study", end_study), ("log", log_cmd)]:
        sp = sub.add_parser(verb); sp.set_defaults(func=fn)
    ss = sub.add_parser("start-study"); ss.add_argument("topic", nargs="*"); ss.add_argument("-k", "--kind", default="study"); ss.set_defaults(func=start_study)
    t = sub.add_parser("task"); ts = t.add_subparsers(dest="sub")
    ta = ts.add_parser("add"); ta.add_argument("text", nargs="+"); ta.add_argument("-p", "--priority", default="med", choices=list(PRI)); ta.add_argument("-t", "--time", type=int); ta.set_defaults(func=task_add)
    td = ts.add_parser("done"); td.add_argument("n", type=int); td.set_defaults(func=task_done)
    ts.add_parser("ls").set_defaults(func=task_ls); t.set_defaults(func=task_ls)
    sk = sub.add_parser("skill"); sks = sk.add_subparsers(dest="sub")
    ska = sks.add_parser("add"); ska.add_argument("name"); ska.add_argument("-c", "--category", default="general"); ska.add_argument("-l", "--level", default="beginner"); ska.add_argument("-g", "--goal", default="interview-ready"); ska.set_defaults(func=skill_add)
    skset = sks.add_parser("set"); skset.add_argument("name"); skset.add_argument("fields", nargs="+"); skset.set_defaults(func=skill_set)
    sks.add_parser("ls").set_defaults(func=skill_ls); sk.set_defaults(func=skill_ls)
    d = sub.add_parser("dsa"); ds = d.add_subparsers(dest="sub")
    da = ds.add_parser("add"); da.add_argument("name", nargs="+"); da.add_argument("-p", "--pattern", default=""); da.add_argument("-d", "--difficulty", default="med"); da.add_argument("-u", "--url", default=""); da.set_defaults(func=dsa_add)
    dsv = ds.add_parser("solved"); dsv.add_argument("n", type=int); dsv.add_argument("--hint", action="store_true"); dsv.add_argument("--solution", action="store_true"); dsv.add_argument("-m", "--mistake", default=""); dsv.set_defaults(func=dsa_solved)
    dls = ds.add_parser("ls"); dls.add_argument("--due", action="store_true"); dls.set_defaults(func=dsa_ls); d.set_defaults(func=dsa_ls, due=False)
    cr = sub.add_parser("career"); crs = cr.add_subparsers(dest="sub")
    cra = crs.add_parser("add"); cra.add_argument("company"); cra.add_argument("role"); cra.add_argument("-u", "--url", default=""); cra.add_argument("-r", "--resume", default=""); cra.add_argument("--applied", action="store_true"); cra.set_defaults(func=career_add)
    crst = crs.add_parser("status"); crst.add_argument("n", type=int); crst.add_argument("stage"); crst.set_defaults(func=career_status)
    crs.add_parser("ls").set_defaults(func=career_ls); cr.set_defaults(func=career_ls)
    return p

def main():
    argv = sys.argv[1:]
    if not argv:
        return dashboard()
    p = build_parser()
    args = p.parse_args(argv)
    fn = getattr(args, "func", None)
    if fn: fn(args)
    else: dashboard()

if __name__ == "__main__":
    try: main()
    except KeyboardInterrupt: print(); sys.exit(130)
