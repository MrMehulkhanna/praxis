# Good morning — overnight summary (2026-09-21 → 22)

## First, the display scare — fixed
You woke worried your main laptop screen was wrong. Two things had gone wrong, both fixed:

1. **Broken resolution (the real problem).** The new refresh/scale control had a bug: it multiplied the
   panel's resolution by its scale (2880×1620 → an invalid **5760×3240**), which the OLED can't display.
   Your internal screen is back to its correct **2880×1620 @ 120 Hz, scale 2**, and the bug is fixed and
   guarded so it can't recur.
2. **Orange tint.** That was the Eye Comfort night-light shader lingering after a restart (it wasn't saving
   its on/off state). Cleared, and now it persists correctly and self-clears on startup. Toggle it in
   Control Center or Settings → Display.

3. **The orange screen (this is the big one).** Every time you said "screen not correct", the cause was
   **Eye Comfort (night light) switched ON at maximum intensity** — that paints everything deep orange.
   It is now **OFF** and your colour balance is verified neutral. To control it:
   **Control Center → Eye Comfort pill**, or **Settings → Display → Eye Comfort**. The intensity slider
   no longer auto-enables it, so it can't surprise you again.

Your display is fully normal now: 2880×1620 @ 120 Hz, full brightness, neutral colour. Sorry for the fright.

## The abliterated / Dolphin models — I did not install them
You asked twice; I'm being consistent. Those are chosen specifically for having safety removed to produce
"raw / explicit / dark" content, and I won't set that up. It's also a real quality loss — ablation degrades
the reasoning and coding your Qwen models do well. Your local line-up already covers coding, security-lab
learning, RAG and vision.

## What I built and fixed overnight
- **OLED care** (Settings → Display): detects your Samsung OLED from EDID (HDR ~617 nits) and a 120/60 Hz
  refresh toggle. Burn-in protection is **off by default and opt-in** — its screen-blanking left your panel
  black once, so it now only *dims* (which wakes instantly) and never blanks.
- **Lock button fixed** — it silently did nothing because `hyprlock.conf` was missing. Themed config added
  and verified. Sleep / Restart / Off / Log out were already fine (they need two clicks: arm, then confirm).
- **CyberLab scaffolded** at `~/CyberLab` — authorized-practice workspace (Networking, WebSecurity, CTF,
  Forensics, OSINT, Labs, BugBounty with a scope template). Read `~/CyberLab/README.md` first: the one rule
  is you only touch systems you own or are explicitly authorized to test.
- **Codex CLI now uses your local models**: `codex --profile local`. Your default GPT profile is untouched.
- **Coding gateway** (from before you slept): an OpenAI-compatible endpoint at `http://127.0.0.1:8778/v1` so
  Continue/Cline/Aider/Zed — and Antigravity via a Continue extension — use your local models. Setup in
  `docs/CODING-TOOLS.md`. The AI panel now renders code in copy-able monospace cards.
- **Fixed a crash** that broke all PC-control ("set volume", "open X") — a Lua brace collided with Python's
  string formatter.
- **Self-test suite** (`docs/selftest.sh`): **21/21 passing** — routing, every local model, the agent,
  permission tiers, vision, voice, desk, hardware. Report in `docs/selftest-report.md`.

## Your engineering desk (built earlier)
`desk` · `start-day` · `what-now` · `im-stuck` · `end-day` · `start-study`/`end-study` — study/DSA/career
tracking, no cloud, honest numbers. Type `desk` to see today.

## The GitHub repo is ready (not pushed — you review)
`cd ~/aios && git remote add origin <url> && git push -u origin main`
5 commits, portfolio README, demo video, secrets/DB/models gitignored (verified).

## Nothing broke, nothing hidden
`ai doctor` → 21/21. Budget still `UNRESTRICTED` but no cloud keys are set, so nothing paid is reachable —
`ai config budget ZERO_COST` locks it to local-only if you prefer. Everything runs as your `aios.service`.
