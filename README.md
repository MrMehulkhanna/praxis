<p align="center"><img src="docs/assets/praxis.svg" width="88" alt="Praxis"></p>
<h1 align="center">Praxis</h1>
<p align="center"><i>knowledge, put into action</i></p>
<p align="center"><b>An Arch-based Linux desktop with a local-first AI built in.</b><br>
Boot it from a USB stick, try it, install it next to Windows — then ask your computer questions, offline.</p>

<p align="center">
  <a href="https://github.com/MrMehulkhanna/praxis/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/MrMehulkhanna/praxis/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Arch Linux" src="https://img.shields.io/badge/Arch_Linux-based-1793D1?logo=archlinux&logoColor=white">
  <img alt="Wayland" src="https://img.shields.io/badge/Wayland-Hyprland-58E1FF?logo=wayland&logoColor=black">
  <img alt="Qt/QML" src="https://img.shields.io/badge/Qt_6_%2F_QML-41CD52?logo=qt&logoColor=white">
  <img alt="Python" src="https://img.shields.io/badge/Python-FastAPI_%2F_asyncio-009688?logo=fastapi&logoColor=white">
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-FTS5_%2B_vec0-003B57?logo=sqlite&logoColor=white">
  <img alt="llama.cpp" src="https://img.shields.io/badge/llama.cpp-CUDA_%2F_Vulkan-76B900?logo=nvidia&logoColor=white">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue">
</p>

---

Most "AI desktops" are a chat box bolted onto a window manager. Praxis is built the other way round:
a small backend owns a **context store**, a **model gateway**, a **permission layer** and a **usage
ledger** — and every surface (the Wayland shell, a browser UI, a CLI, voice) is just a client of it.
Pick a model once and it applies everywhere. Nothing leaves the machine unless you add a cloud key.

It is developed on a 16 GB laptop with a **6 GB** GPU — the constraint behind most design decisions —
but nothing in the image assumes that machine: GPU drivers, model offload, brightness limits and the
hardware panels all adapt to the computer it is installed on.

## Get it

> 📖 **Step-by-step instructions, partitioning tips, and hardware troubleshooting: See the [Complete Installation Guide](docs/INSTALLATION.md).**

1. **Download** the ISO from [Releases](https://github.com/MrMehulkhanna/praxis/releases) (≈ 1.9 GB) — or build it yourself on Arch:
   `bash iso/build.sh` (≈ 5 min with a warm package cache).
2. **Write it to a USB drive:** `bash iso/flash.sh praxis-*.iso` — refuses anything that isn't a USB disk,
   wipes the old partition table, writes, then reads the drive back and compares checksums.
3. **Boot** it (UEFI, Secure Boot off). The live desktop logs in as `praxis` / `praxis`.
4. Click **Install Praxis Linux** in the dock — a graphical installer (a text one is a click away):
   - **next to Windows**: makes Windows' drive smaller with a slider, after checking it can — BitLocker,
     Fast Startup/hibernation and an unhealthy NTFS are explained instead of risked. A test run comes
     first, the partition table is saved, and the volume is verified before anything else changes;
   - or **free space**, **one partition you choose**, or **the whole disk** (you tick a box first);
   - **btrfs with snapshots** (one before every update, bootable from the GRUB menu) or ext4;
   - optional app bundles (Office, Developer, Media, Creative, Gaming with 32-bit drivers, Chat, …);
   - detects CPU microcode and GPU drivers by PCI vendor ID (Intel, AMD, NVIDIA — including hybrid
     laptops and pre-Turing cards, which get the open-source stack);
   - GRUB + os-prober: Windows and any other OS are in the boot menu; the clock agrees with Windows.
5. After the first login, `aios-setup` installs the AI backend and `praxis-models recommend` suggests models
   that fit your GPU.

## The desktop

<p align="center"><img src="docs/screenshots/settings-wallpaper.png" width="760" alt="Settings — still and live wallpapers"></p>

| | |
|---|---|
| **Shell & Monitoring** | Qt 6/QML on [Quickshell](https://quickshell.org): responsive top bar with **live system monitoring** (CPU %, RAM, GPU VRAM, network speeds, temperatures), launcher & command palette, Control Center, StandBy-style widget board, a 12-desk overview, and notifications. |
| **Date & Time Control** | Dedicated Settings panel with automatic GeoIP timezone detection, one-click NTP time synchronization, interactive timezone picker, and Windows dual-boot clock adjustment. Top-bar clock is always visible with right-click instant auto-sync. |
| **Hugging Face AI Models** | Download GGUF models directly from Hugging Face into AIOS (Qwen 2.5, DeepSeek, Mistral, Llama, Dolphin) through the AI panel or Settings. One-click downloads with automatic quant selection and hardware VRAM fit checking. |
| **Cloud API Gateways** | Easy configuration for Anthropic Claude, OpenAI, Google Gemini, Groq, and OpenRouter in Settings with strict budget modes (₹0 Zero Cost, Free Online tiers, Approval required, or Unrestricted). |
| **Voice Typing (Dictation)** | Press `Super+H`, speak, press `Super+H` again: your words are transcribed locally via Whisper and typed into whatever window has focus (terminal, browser, editor). Includes a dedicated Voice Typing button in the top bar with active animation and 4-finger trackpad gesture. |
| **Microphone Privacy Indicator** | Top-bar microphone indicator shows active hardware recording in real-time, displays mute status (`mic-off`), and allows one-click mute toggling or scroll volume adjustments. |
| **Dock Elevation & Auto-Hide** | Floating dock with customizable bottom lift/elevation, auto-hide on hover, fullscreen auto-hide, and option to completely hide on laptops for maximum vertical screen space. |
| **Touchpad Gestures** | 3-finger horizontal swipe for interactive workspace switching; 4-finger swipe down for instant voice typing dictation. |
| **Audio Auto-Switching** | PipeWire automatically switches default sink and source when Bluetooth earphones, headsets, or USB audio devices connect or disconnect. |
| **Settings that do real things** | Live Wi-Fi scan and rescan, Bluetooth pairing, PipeWire audio routing, idle sleep timer, OLED-safe brightness, power profiles, and GPU mode switching. |
| **Task manager** | `Ctrl+Shift+Esc`: *current* CPU per process, per-process GPU use from kernel DRM counters and `nvidia-smi`, with clean termination and an instant Stop button for running AI jobs. |
| **Wallpapers** | Thirteen original stills and three seamless live loops decoded on the iGPU to allow the dGPU to sleep. |
| **Modes** | Control Center: **AI on/off**, **Game mode** (performance profile, suppresses notifications/blur/animations), and **Battery saver** (switches screen to 60 Hz, still wallpaper on battery). |
| **Freeze protection** | zram tuned to RAM, MGLRU thrashing protection, and earlyoom: out-of-memory stops the AI model server first — never the compositor. |
| **Passwordless Updates** | `praxis-doctor` checks and fixes system health; `praxis-update` pulls latest desktop and AIOS bugfixes directly from GitHub with zero password prompts. |
| **UEFI Bootloader Setup** | Automatically configures GRUB and sets Praxis as primary in UEFI NVRAM `BootOrder` across all motherboards (HP, Acer, Dell, Lenovo, ASUS). |

<p align="center">
  <img src="docs/screenshots/live-nebula.jpg" width="250" alt="Nebula live wallpaper">
  <img src="docs/screenshots/live-aurora.jpg" width="250" alt="Aurora live wallpaper">
  <img src="docs/screenshots/live-horizon.jpg" width="250" alt="Horizon live wallpaper">
</p>

**Keys:** `Super+Space` palette · `Super+A` launcher · `Super+I` AI · `Super+O` Control Center ·
`Super+B` widgets · `Super+Tab` desks · `Ctrl+Shift+Esc` tasks · `Super+N` quick note ·
`Super+H` voice typing · `Super+G` Game mode · `Super+Shift+V` clipboard · `Super+.` emoji ·
`Super+Shift+O` OCR · `Print` / `Super+Shift+S` screenshot · `Super+Shift+R` record · `Super+Esc` restart the shell.

---

## Engineering highlights

The parts worth reading, and why they're built that way.

### Context engine — retrieval under a token budget
`src/core/context/engine.py`
Naively you send the whole conversation; it gets expensive and worse over time. Instead: retrieve
candidates from SQLite FTS5, score them `0.45·BM25 + 0.25·recency + 0.30·importance`, dedup, and
**stop early** once the budget is met — hard-capped at 50% of the context window, recent turns at 25%.

### Model gateway — provider independence
`src/core/gateway/`, `src/adapters/`
One `Adapter` protocol. A local llama.cpp adapter — which sizes the GPU offload to the machine's free
VRAM — plus a generic OpenAI-compatible adapter that serves 8 cloud providers from a JSON config.

### Stopping work for real
`src/core/activity.py`
A stop races every pending token read against a cancel event, so it takes effect even during prompt
processing; cancelling the read closes the stream, and llama-server stops computing. A client that
disconnects mid-answer can no longer leave a job "running" forever — that cancellation used to skip
every clean-up path. Tests pin all of it.

### Cost safety as structure, not a flag
`src/core/gateway/gate.py`
A paid provider is **unreachable** unless the budget mode allows it — the check sits at a choke point
every request crosses, before any HTTP request is built.

### Default-deny permissions for AI-generated commands
`src/core/perms/policy.py`, `src/core/tools/exec.py`, `voice/`
The model proposes one shell command; a classifier sorts it **auto / confirm / forbidden**. A command
must positively match a safe allow-list to run unattended; read-only commands are demoted the moment
their output is redirected. Voice has its own allow-list. Every decision lands in an audit table.

### An installer that other people can trust
`iso/airootfs/usr/local/bin/praxis-install-engine`, `iso/test-install.sh`, `tests/iso_checks.sh`
Both installers (graphical and text) only collect answers; one engine does the work from a plan file,
so the whole thing can be tested without a person. `iso/test-install.sh` builds disk images — including
a fake Windows 11 disk with EFI, MSR, an NTFS C: full of files and a recovery partition — installs into
them with the real engine, checks the result on disk (Windows' files hash-identical after the shrink,
recovery partition and Windows' boot files untouched), then boots each one in QEMU and checks the
running system through the guest agent. ~130 static checks run on every push: GPU detection against
real `lspci` lines, free-space detection, the engine's safety rules, installed-system/live-session
package parity, every package the installers or app bundles request existing, keybinds calling only
shipped tools, and the live image's network and SSH policy.

## Architecture

```mermaid
flowchart LR
  subgraph Surfaces
    shell[Quickshell desktop]:::s
    cli[ai CLI]:::s
    voice[Voice]:::s
    ide[IDEs via /v1]:::s
  end
  shell & cli & voice & ide --> api[FastAPI backend]
  api --> router[router<br/>task → model]
  router --> gate[budget gate]
  gate --> ctx[context engine<br/>FTS5 + vectors]
  ctx --> ad{adapter}
  ad --> llama[llama-server<br/>local GPU]
  ad --> cloud[OpenAI-compatible<br/>cloud, opt-in]
  api --> perms[permission layer] --> exec[shell tools]
  api --> bus[activity bus] --> shell
  classDef s fill:#1f2532,stroke:#7aa2f7,color:#edf2f7
```

Independent modules under `src/core/`: `store` · `context` · `gateway` · `providers` · `router` ·
`perms` · `tools` · `agent` · `activity` · `hardware` · `voice` · `rag`.

## The CLI

```console
$ ai "check my GPU and memory"        # agent — gathers real diagnostics, then answers
$ ai code "add a retry to this fn"    # routes to a coding-capable model, adds cwd + git context
$ ai see diagram.png "what's wrong?"  # local vision model
$ ai do "set volume to 40%"           # permission-gated system control
$ ai rag add ~/notes; ai rag q "…"    # your own documents, retrieved locally
$ ai doctor                           # health check for this machine
$ praxis doctor --fix                 # …and the fixes that are safe to automate
$ praxis mode game on                 # Game mode (also: ai off, saver on)
```

## Layout

```
src/        FastAPI backend (core/ modules + adapters/)
ai          the CLI
voice/      push-to-talk pipeline + default-deny command allow-list
desktop/    Quickshell shell, Hyprland/swaync/rofi config, wallpapers (still + live)
iso/        archiso profile overlay, build/flash/publish scripts, installer
tests/      pytest (backend, voice) + iso_checks.sh
tools/      wallpaper generators (still + live), hardware helper, desk tracker
```

## Develop

On an existing Arch + Hyprland system:

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
cp config/aios.env.example config/aios.env && chmod 600 config/aios.env
systemctl --user enable --now aios.service
.venv/bin/python -m pytest tests/ && bash tests/iso_checks.sh
sudo iso/test-install.sh alongside-btrfs wipe-ext4      # real installs into disk images, booted in QEMU
```

`ai doctor` names anything missing. `docs/selftest.sh` runs 21 end-to-end checks on a live system.

## Principles

Local-first · model-agnostic · context-centric · cost-aware · offline-capable · user-controlled ·
modular · transparent. No hidden automation, no telemetry.

## License

MIT — see [`LICENSE`](LICENSE). Model weights, `llama.cpp` and the packages in the ISO are separate
projects under their own licenses. Praxis is an unofficial project and is not affiliated with Arch Linux.
