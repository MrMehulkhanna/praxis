<h1 align="center">Praxis</h1>
<p align="center"><i>knowledge, put into action</i></p>
<p align="center"><b>A local-first AI operating environment for Linux.</b><br>
The machine owns the ecosystem. Local and cloud models are interchangeable engines behind one gateway.</p>

<p align="center">
  <img alt="Arch Linux" src="https://img.shields.io/badge/Arch_Linux-1793D1?logo=archlinux&logoColor=white">
  <img alt="Wayland" src="https://img.shields.io/badge/Wayland-Hyprland-58E1FF?logo=wayland&logoColor=black">
  <img alt="Qt/QML" src="https://img.shields.io/badge/Qt_6_%2F_QML-41CD52?logo=qt&logoColor=white">
  <img alt="Python" src="https://img.shields.io/badge/Python-FastAPI_%2F_asyncio-009688?logo=fastapi&logoColor=white">
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-FTS5_%2B_vec0-003B57?logo=sqlite&logoColor=white">
  <img alt="llama.cpp" src="https://img.shields.io/badge/llama.cpp-CUDA-76B900?logo=nvidia&logoColor=white">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue">
</p>

---

Most "AI desktops" are a chat box bolted onto a window manager. Praxis is built the other way round:
a small backend owns a **context store**, a **model gateway**, a **permission layer** and a **usage
ledger** — and every surface (a Wayland shell, a browser UI, a CLI, voice) is just a client of it.
Pick a model once and it applies everywhere.

It runs on a 16 GB laptop with a **6 GB** GPU, which is the constraint that shaped nearly every
design decision here. Default mode is offline and zero-cost: nothing leaves the machine unless a
provider is explicitly configured.

## Demo

`docs/praxis-demo.mp4` — 90 seconds: launcher, live Control Center, a local model answering, the
activity pipeline, Settings, and the CLI.

---

## Engineering highlights

The parts worth reading, and why they're built that way.

### Context engine — retrieval under a token budget
`src/core/context/engine.py`
Naively you send the whole conversation; it gets expensive and worse over time. Instead: retrieve
candidates from SQLite FTS5, score them `0.45·BM25 + 0.25·recency + 0.30·importance`, dedup, and
**stop early** once the budget is met — hard-capped at 50% of the context window, recent turns at 25%.
The goal is maximum *useful* context per token, not maximum context.

### Model gateway — provider independence
`src/core/gateway/`, `src/adapters/`
One `Adapter` protocol. A local llama.cpp adapter, plus a generic OpenAI-compatible adapter that
serves 8 cloud providers from a JSON config. Removing a provider can't break the system; adding one
is a config entry, not a rewrite.

### Cost safety as structure, not a flag
`src/core/gateway/gate.py`
A paid provider is **unreachable** unless the budget mode allows it — the check sits at a choke point
every request path must cross, before any HTTP request is constructed. A boolean someone forgets to
check is how you get a surprise bill; make the unsafe path impossible to reach by accident.

### Default-deny permissions for AI-generated commands
`src/core/perms/policy.py`, `src/core/tools/exec.py`
The model proposes one shell command; a classifier sorts it **auto / confirm / forbidden**. Default is
`confirm` — a command must positively match a safe allow-list to run unattended. Read-only commands
are demoted the moment their output is redirected (`echo` stops being read-only when it writes a
file). Every decision lands in an audit table.

### Resource-aware scheduling on a 6 GB GPU
`src/adapters/local/llama.py`, `src/core/router.py`
Models load on first use and unload after idle so the compositor stays smooth. The router classifies
each request (code / debug / sysadmin / reasoning / vision) and picks a model — but **prefers the
already-loaded one** when it's a close-enough fit, because a swap costs 10–20 s. The theoretically
better model isn't better if switching costs more than the quality gain.

### API surface
`src/app.py`
Streaming SSE chat, plus **OpenAI-compatible** `/v1/chat/completions` *and* the newer `/v1/responses`
API — so Codex CLI, Continue, Aider and Zed drive local models through the same routing and cost gate.

### Desktop shell
`desktop/` — Qt6/QML on [Quickshell](https://quickshell.org)
Per-monitor top bar, dock, launcher, Control Center, AI panel, activity feed and a Settings app whose
controls mutate real system state: Hyprland options via its Lua IPC, NetworkManager and BlueZ over
D-Bus, PipeWire nodes, power-profiles-daemon, and ASUS hardware through `/sys` with polkit for
root-only writes.

---

## Architecture

```
UI / CLI / voice
  → /api/ask         classify → is this about the machine? ── yes ──► agent (gather evidence → answer → propose fix)
                                                   └── no ──► chat
  → router.resolve   selected model | auto → choose(task, available, loaded, budget, online, vision)
  → budget gate      cloud? free? approved?   (blocks anything that would leave the machine)
  → context engine   relevant memory only — never the whole DB
  → adapter.run      llama-server (local)  |  OpenAI-compatible (cloud)   — streamed as SSE
  → store + ledger   messages linked in a graph · run row (tokens, latency, cost, status)
  → activity bus     every stage visible live in the UI and `ai logs -f`
```

Independent modules under `src/core/`: `store` · `context` · `gateway` · `providers` · `router` ·
`perms` · `tools` · `agent` · `activity` · `hardware` · `voice`.

## The CLI

```console
$ ai "check my GPU and memory"        # agent — gathers real diagnostics, then answers
$ ai code "add a retry to this fn"    # routes to the code model, adds cwd + git context
$ ai see diagram.png "what's wrong?"  # local vision model
$ ai do "set volume to 40%"           # permission-gated system control
$ ai model auto | models | usage      # one shared selection · measured tok/s · per-model ledger
$ ai doctor                           # 21-point health check
```

## Layout

```
src/          FastAPI backend (core/ modules + adapters/)
ai            the CLI
voice/        push-to-talk pipeline + default-deny command allow-list
desktop/      Quickshell shell (Config/ Services/ components/ windows/)
tools/        desk — a study/DSA/career tracker with no cloud and no invented stats
config/       providers.json + aios.env.example
docs/         architecture, audit, self-test, demo
```

> The backend daemon and its paths are named `aios` (AI Operating System) — Praxis is the project;
> `aios` is the service inside it.

## Setup

Arch + Hyprland, `quickshell`, `swaync`, PipeWire, a CUDA `llama.cpp` build, and a Python venv.

```bash
cp config/aios.env.example config/aios.env && chmod 600 config/aios.env
python -m venv .venv && .venv/bin/pip install fastapi uvicorn httpx faster-whisper sqlite-vec
systemctl --user enable --now aios.service
ln -sf "$PWD/ai" ~/.local/bin/ai
```

`ai doctor` verifies every dependency and names what's missing.

## Testing

`docs/selftest.sh` — 21 checks across routing, every local model, the agent, permission tiers,
vision, voice and hardware. Report in `docs/selftest-report.md`.

## Principles

Local-first · model-agnostic · context-centric · cost-aware · offline-capable · user-controlled ·
modular · transparent. No hidden automation, no telemetry, no monolith.

## License

MIT — see [`LICENSE`](LICENSE). Model weights and `llama.cpp` are separate projects under their own licenses.
