# Defending AIOS in an interview

You have **one** substantial project. The job now is not to build more — it's to be able to
defend this one so well that an interviewer believes you. Right now you can't, because you
didn't write most of it. That is fixable in about two weeks of honest work, and it's the
highest-leverage thing you can do.

**The rule:** you may say *"I designed and directed this system, and I used AI heavily as a
coding assistant."* That is true, increasingly normal, and defensible. What gets you rejected
is claiming you hand-wrote it and then failing to explain a design decision. Interviewers
don't punish AI use. They punish not understanding your own system.

---

## The 60-second pitch (memorise the shape, not the words)

> AIOS is a local-first AI operating environment on Arch/Hyprland. The idea: my machine owns the
> ecosystem, and models — local or cloud — are interchangeable engines behind one gateway. A FastAPI
> backend owns a SQLite context store, a model gateway, a permission layer and a usage ledger. Four
> front-ends — a Quickshell desktop shell, a browser UI, a CLI, and voice — are all clients of that
> same backend, so one model selection applies everywhere. It runs on a 6 GB laptop GPU, so models
> load on demand and auto-unload. Default mode is zero-cost: nothing leaves the machine unless I
> explicitly configure a provider.

---

## The five decisions you must be able to defend

These are the real engineering choices in this codebase. Learn *why*, not just *what*.

### 1. Why a context **engine**, not just sending chat history?
`src/core/context/engine.py`. Naively you'd send the whole conversation. That's expensive and gets
worse over time. Instead: retrieve candidates (SQLite FTS5), score them (`0.45×BM25 +
0.25×recency + 0.30×importance`), dedup, and **stop early** once the budget is met — capped at
50% of the context window, with recent turns capped at 25%.
- *Why stop early?* Maximum useful context per token, not maximum context. Filling the window
  slows inference and, on a paid provider, costs money.
- *Interviewer follow-up:* "How would you improve retrieval?" → embeddings/vector search
  (the schema already has a `vec0` table); currently keyword BM25, which misses paraphrases.

### 2. Why a model **gateway** with adapters?
`src/core/gateway/iface.py`, `src/adapters/`. One `Adapter` protocol; a local llama.cpp adapter and
a generic OpenAI-compatible adapter that serves 8 cloud providers from a JSON config.
- *Why?* Removing a provider must not break the system. Adding one is a config entry, not a rewrite.
- *Follow-up:* "What's the hard part?" → capability differences (vision, tool-calling) and
  normalising streaming formats between providers.

### 3. Why is the cost gate **structural** instead of a flag?
`src/core/gateway/gate.py`. A paid provider is unreachable unless the budget mode allows it — the
check sits at a choke point every path must cross, before any HTTP request is built.
- *Why does that matter?* A boolean someone forgets to check is how you get a surprise bill.
  Make the safe thing the default and the unsafe thing impossible to reach by accident.
- This is a **security-mindset answer** — very good signal for both SDE and security roles.

### 4. Why a permission layer for AI-generated commands?
`src/core/perms/policy.py`, `src/core/tools/exec.py`. The model proposes one shell command; a
classifier sorts it into **auto / confirm / forbidden**. Default is `confirm` — a command must
positively match a safe allow-list to run unattended. Everything is written to an audit table.
- *Why default-deny?* Unknown should never mean "allowed."
- *Nice detail to mention:* read-only commands get demoted to `confirm` if their output is
  redirected (`>`), because `echo` stops being read-only the moment it writes a file.

### 5. Why does the model auto-unload, and why "stickiness" in routing?
`src/adapters/local/llama.py`, `src/core/router.py`. 6 GB VRAM. Models load on first use and unload
after idle so the desktop stays smooth. The router prefers the *already-loaded* model when it's a
close-enough fit, because swapping models costs 10–20 s.
- *This is a real systems-thinking answer:* the theoretically-best model isn't best if switching
  to it costs more than the quality gain.

---

## Prove it to yourself (do these — they're the actual work)

You cannot fake these. Each one forces understanding.

- [ ] **Read and annotate** `context/engine.py` (95 lines). Write, in your own words, what each of
      the three scoring weights does and what happens if you set `MIN_SCORE` to 0.
- [ ] **Change something and predict the result first.** Set `W_RECENCY = 0.8`, predict how
      retrieval changes, then test with `ai --verbose "..."` and compare to your prediction.
- [ ] **Add one forbidden pattern** to `policy.py` (e.g. `shutdown`), then write a test proving it's
      blocked. You now own that file.
- [ ] **Trace one request end-to-end** with `ai logs -f` open in another terminal. Write the path:
      CLI → `/api/ask` → classify → route → gate → context → adapter → ledger.
- [ ] **Break it on purpose.** Stop the backend and describe exactly which failure the CLI shows and
      why (exit code 3). Fixing something you broke is how you learn a system.
- [ ] **Explain the SSE bug** we hit: an event type applies to one data field only, and not resetting
      it silently swallowed every token. This is a *great* debugging story — you can tell it.

## Questions you will be asked

1. "Walk me through what happens when you type a question." (the flow above)
2. "Why SQLite and not Postgres?" → single user, single machine, zero ops, FTS5 built in; Postgres
   if it ever became multi-user/networked.
3. "How do you stop it sending private data to a cloud provider?" → the gate; default ZERO_COST.
4. "What's the weakest part?" → **answer honestly**: keyword retrieval instead of embeddings; no
   tests around the context engine; the shell is tightly coupled to Hyprland. Naming real
   weaknesses is a strength signal.
5. "What did AI write vs. you?" → *"I designed the architecture and made the decisions; I used AI
   heavily to write code. Here's a decision I changed and why…"* Then tell the SSE bug story or the
   cost-gate reasoning.

---

## What to do with this

Two weeks, ~45 min/day, working through the checklist above. At the end you'll have a flagship
project you can genuinely defend — which beats 50 repos you can't explain, every single time.

Then build **two** more, small and yours:
1. A CRUD web app (auth + DB + REST + deployed) — proves you can ship standard software.
2. A focused ML/RAG app you build yourself — proves the AI specialisation is real.

Three defensible projects. That's the target. Not fifty.
