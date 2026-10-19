# AIOS — system map

Local-first AI operating environment on Arch Linux. One machine owns the ecosystem;
models (local or cloud) are interchangeable engines behind one gateway.

```
Existing System
├── OS/base layer        Arch Linux · kernel 7.2 · Hyprland 0.56 (Lua config ~/.config/hypr/hyprland.lua)
│                        PipeWire · NetworkManager · BlueZ · swaync · hyprpaper · hyprlock · polkit-kde agent
├── AI layer             ~/aios/src  (FastAPI, systemd user unit aios.service, 127.0.0.1:8778)
│   ├── core/context     retrieval → rank → dedup → budget → stop-early (SQLite FTS5 + sqlite-vec)
│   ├── core/store       aios.db: objects · edges · chunks · assets · runs (ledger) · grants · audit · kv
│   ├── core/router      task classifier (code/debug/sysadmin/reasoning/general) + model chooser
│   ├── core/gateway     Request/Adapter protocol · budget gate (ZERO_COST default)
│   ├── core/providers   provider manager: local + OpenAI-compatible cloud (config/providers.json)
│   ├── core/perms       risk policy: auto / confirm / forbidden
│   ├── core/tools       gated command execution + audit
│   ├── core/agent       terminal agent: evidence gathering → answer → RUN:/FIX: rounds
│   ├── core/activity    event bus (SSE) → Activity panel, `ai logs -f`, logs/activity.log
│   ├── core/hardware    /sys + nvidia-smi view; pkexec for root-only toggles
│   └── core/voice       warm faster-whisper transcription (idle-unloaded)
├── Local models         ~/aios/models  (llama.cpp CUDA build, llama-server on :8779, idle auto-unload)
│   ├── qwen3-4b         Daily · fast · ~2.6 GB VRAM
│   ├── qwen3-8b         Quality · partial offload (RAM) · medium
│   ├── qwen3-vl-8b      Quality + vision (images / video frames) · partial offload
│   └── qwen-coder-7b    Code specialist
├── Cloud models         config/providers.json — Groq · OpenRouter · Gemini · Mistral · Cerebras · GitHub · Anthropic · OpenAI
│                        all DISABLED until key (config/aios.env, 0600) + enabled + budget mode ≠ ZERO_COST
├── Model router         auto: task → role preference → stickiness to the loaded model → cloud only if opted in
├── Voice control        ~/aios/voice: pw-record → /api/voice/transcribe → security.py allow-list → act / ask agent → piper TTS
├── CLI                  ~/aios/ai  (→ ~/.local/bin/ai, `aios` alias)  ai "<question>" · ai do · ai model · ai models …
├── GUI/UI               ~/.config/quickshell (Quickshell 0.3): TopBar · Dock · Launcher · ControlCenter · AiPanel ·
│                        ActivityPanel · SettingsWindow  +  browser UI at http://127.0.0.1:8778
├── System controls      Control Center + Settings (Wi-Fi/BT/audio/brightness/power profile/DND/hyprctl options)
├── Hardware controls    platform profile · fan auto/full · keyboard backlight · charge limit (pkexec) · GPU MUX (read)
├── Monitoring           Activity panel · bar stats (profile-dependent) · ai system/gpu/cpu/memory/storage · ai usage
├── Storage management   ai cleanup (bak/pycache/old backups) · models never auto-deleted
├── Networking           Quickshell.Networking (NM) — join/forget/toggle from Settings
├── Developer tools      ai code (cwd + git context → coder model) · Antigravity launcher (when installed)
├── Automation           quickshell ipc call shell {open|toggle|ask|control|search|settings|profile} · voice phrases
└── Project structure    ~/aios (backend, models, voice, docs) · ~/.config/quickshell (shell) · ~/.config/hypr (WM)
```

## Request flow

```
UI / CLI / voice
  → /api/ask            classify → diagnostic?  ── yes ──► core/agent (gather evidence, answer, RUN:/FIX:)
                                          └── no ───► /api/chat
  → router.resolve      selected model | auto → choose(task, available, loaded, budget, online)
  → budget gate         cloud? free? approved?  (ZERO_COST blocks everything that leaves the machine)
  → context engine      relevant memory only (never the whole DB)
  → adapter.run         llama-server (local) | OpenAI-compatible (cloud)   — streamed as SSE
  → store + ledger      message objects linked · runs row (tokens, ms, cost, status)
  → activity bus        every stage visible in the Activity panel / ai logs -f
```

## Where things live

| Thing | Path |
|---|---|
| Backend service | `systemctl --user {status,restart} aios.service` · `~/aios/run.sh` |
| Secrets | `~/aios/config/aios.env` (0600) |
| Providers | `~/aios/config/providers.json` |
| Budget / model / thinking | `ai config` (stored in aios.db kv) |
| Shell settings | `~/.config/quickshell/settings.json` |
| Voice allow-list | `~/aios/voice/voice_permissions.json` |
| Logs | `~/aios/logs/activity.log`, `voice_audit.jsonl`, `journalctl --user -u aios` |
| Wallpapers | `~/.local/share/wallpapers` |

## Keys

Super+A / Super+W launcher · Super+I AI · Super+O Control Center · Super+Esc restart shell ·
right-click the AI chip → Activity · hold the mic → voice.
