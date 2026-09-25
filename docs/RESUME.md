# Praxis on your resume

Copy-paste material. **Every line here is defensible** — you can point at the file that backs it.
Read `INTERVIEW-PREP.md` before you use any of it, because you'll be asked to explain these.

---

## Project entry (long form — for a project section)

**Praxis — Local-First AI Operating Environment** · *Python, FastAPI, Qt6/QML, SQLite, Wayland, llama.cpp*
`github.com/<you>/praxis`

- Built a local-first AI environment where a single backend owns the context store, model gateway,
  permission layer and usage ledger; a Wayland shell, browser UI, CLI and voice pipeline all operate
  as clients of the same service.
- Designed a **token-budgeted retrieval engine** (SQLite FTS5) that ranks context by BM25, recency and
  importance, deduplicates, and stops early at 50% of the model's window — optimising for useful
  context per token rather than maximum context.
- Implemented a **provider-independent model gateway** behind one adapter protocol, serving local
  llama.cpp models and 8 OpenAI-compatible cloud providers from declarative config; removing a
  provider requires no code change.
- Enforced **cost safety structurally**: paid providers are unreachable unless the budget mode allows
  it, checked at a single choke point before any request is constructed — not a flag a caller can forget.
- Built a **default-deny permission layer** for AI-generated shell commands (auto / confirm / forbidden)
  with an audit trail; read-only commands are demoted when their output is redirected.
- Engineered for a **6 GB VRAM** constraint: on-demand model loading with idle unloading, and a router
  that prefers the resident model when it is a close-enough fit, avoiding 10–20 s swap costs.
- Exposed **OpenAI-compatible `/v1/chat/completions` and `/v1/responses`** endpoints so external tools
  (Codex CLI, Continue, Aider, Zed) drive local models through the same routing and safety gates.
- Wrote a 21-check self-test suite covering routing, model inference, agent behaviour, permission
  tiers, vision, voice and hardware.

## Project entry (short form — 3 bullets, when space is tight)

**Praxis — Local-First AI Operating Environment** · *Python, FastAPI, Qt6/QML, SQLite, Wayland*
- Built a local-first AI environment: one backend owning context retrieval, model routing, a
  permission layer and a usage ledger, with a Wayland shell, CLI and voice pipeline as clients.
- Designed token-budgeted context retrieval (FTS5 + BM25/recency/importance ranking) and a
  provider-independent model gateway serving local llama.cpp models and 8 cloud providers.
- Engineered around a 6 GB VRAM limit with on-demand model loading and residency-aware routing;
  enforced default-deny permissions for AI-generated commands with a full audit trail.

## One-liner (LinkedIn headline / summary)

> Built Praxis — a local-first AI operating environment for Linux: context-budgeted retrieval, a
> provider-independent model gateway, and a default-deny permission layer, running entirely on a
> 6 GB laptop GPU.

---

## Skills this project legitimately demonstrates

Put these in your skills section **only** where the claim is real for you after the deep-dive work.

| Area | What backs it |
|---|---|
| **Python (async)** | FastAPI, `asyncio` subprocess management, async generators, SSE streaming |
| **API design** | OpenAI-compatible Chat Completions + Responses APIs, streaming event protocols |
| **Databases** | SQLite schema design, FTS5 full-text search, graph-style relations, `vec0` vectors |
| **Systems / Linux** | systemd user services, polkit, udev, `/sys` hardware interfaces, D-Bus |
| **Wayland desktop** | Qt6/QML, layer-shell surfaces, Hyprland IPC, NetworkManager + BlueZ over D-Bus, PipeWire |
| **AI/LLM engineering** | Local inference (llama.cpp/CUDA), quantisation & VRAM budgeting, RAG-style retrieval, multimodal (vision) |
| **Security engineering** | Default-deny authorisation model, allow-listing, audit logging, secrets handling |
| **Performance** | Resource-constrained scheduling, model lifecycle management, measured throughput |

---

## How to talk about AI assistance — read this

You will be asked. Have the answer ready, and make it the *true* one:

> "I designed the architecture and made the engineering decisions. I used AI heavily as a coding
> assistant — that's how I work, and it's how a lot of teams work now. What I own is the design:
> why the cost gate is structural instead of a flag, why the router prefers the loaded model, why
> retrieval stops early instead of filling the window."

Then give a concrete example — the SSE bug is a good one: *an event type applies to only the next
data field, and failing to reset it silently swallowed every token after the first event.*

**What sinks candidates is not using AI. It's not being able to explain their own system.** That is
exactly what the exercises in `INTERVIEW-PREP.md` are for — do them before you put this on a resume.

## What NOT to claim

- Don't say you hand-wrote everything. It's untrue and an interviewer will find out in two questions.
- Don't list a skill from the table above that you can't demonstrate in a follow-up question.
- Don't inflate it to "production system serving X users." It's a personal system on one laptop —
  which is *genuinely impressive for a student*. Sell it accurately.
