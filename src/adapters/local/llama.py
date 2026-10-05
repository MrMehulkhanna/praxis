"""
Local llama-server adapter.

Starts llama-server on demand and offloads as much of the model to the GPU as
this machine's free VRAM allows (llama.cpp's -fit), so the same setup suits a
4 GB laptop GPU and a 24 GB desktop card. Auto-unloads after idle — this is
what keeps Hyprland smooth.

KV cache at q8_0 = half the VRAM of fp16 cache.
Flash attention on = faster, lower VRAM for long contexts.
"""
import asyncio, glob, json, os, pathlib, shutil, subprocess, time
import httpx
from core.gateway.iface import Capability, Request, attach_images

HOME     = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))
# A locally built server (AIOS_HOME/llama-server, e.g. a CUDA build) wins;
# otherwise use the distribution's llama-server (Arch: `llama-cpp` + a
# `ggml-vulkan`/`ggml-cuda` backend), so a fresh install works out of the box.
_LOCAL_BIN = HOME / "llama-server"
BIN = _LOCAL_BIN if _LOCAL_BIN.exists() else pathlib.Path(shutil.which("llama-server") or _LOCAL_BIN)
PORT     = int(os.environ.get("LLAMA_PORT", "8779"))
IDLE_SEC = int(os.environ.get("AIOS_IDLE_UNLOAD", "120"))
# generation threads: about half the CPU, leaving the rest for the desktop
THREADS  = int(os.environ.get("AIOS_THREADS", max(2, min(8, (os.cpu_count() or 4) // 2 - 2))))
# on battery: half of that, and no busy-polling between work items — a laptop
# in power-saver mode otherwise spends its whole CPU budget on the model and
# the desktop stops responding while an answer is generated
THREADS_BATTERY = int(os.environ.get("AIOS_THREADS_BATTERY", max(2, THREADS // 2)))
LOG = HOME / "logs" / "llama-server.log"
# On battery an idle model gives the GPU back sooner, so a hybrid laptop's
# NVIDIA GPU can power down between questions.
IDLE_SEC_BATTERY = int(os.environ.get("AIOS_IDLE_UNLOAD_BATTERY", "30"))

def _on_battery() -> bool:
    for status in glob.glob("/sys/class/power_supply/BAT*/status"):
        try:
            if pathlib.Path(status).read_text().strip() == "Discharging":
                return True
        except OSError:
            pass
    return False

def _log_tail(n: int = 6) -> str:
    """Last lines llama-server wrote — the real reason a load failed."""
    try:
        lines = [l for l in LOG.read_text(errors="replace").splitlines() if l.strip()]
    except OSError:
        return ""
    return " | ".join(lines[-n:])[-600:]

# ── model registry ───────────────────────────────────────────────────────
# ngl = layers on GPU (99 = everything). These are only fallbacks for an older
# llama-server without -fit, tuned for a 6 GB GPU next to a compositor; a
# current one sizes the offload to the free VRAM of whatever GPU it finds.
# Setting the profile's env var (e.g. AIOS_8B_NGL) forces a fixed value.
#
# quality: relative local ranking 1–5. No local model on this GPU is
# Claude/GPT-class — that tier only exists as a cloud adapter (paid, opt-in).
PROFILES: dict[str, dict] = {
    "local-qwen3-4b": {
        "dir": "qwen3-4b", "ngl": 99, "ctx": 8192,
        "label": "Qwen3 4B", "role": "Daily",
        "quality": 3, "speed": "fast", "vram": "~2.6 GB", "ram": "~0.5 GB",
        "note": "Best speed/quality balance on 6 GB. Default.",
    },
    "local-qwen3-8b": {
        "dir": "qwen3-8b", "ngl": int(os.environ.get("AIOS_8B_NGL", "28")), "ngl_env": "AIOS_8B_NGL", "ctx": 6144,
        "label": "Qwen3 8B", "role": "Quality",
        "quality": 4, "speed": "medium", "vram": "~4.2 GB", "ram": "~2 GB",
        "note": "Highest-quality local option. Partly in RAM → medium reply time.",
    },
    "local-qwen3-8b-abliterated": {
        "dir": "qwen3-8b-abliterated", "ngl": int(os.environ.get("AIOS_UNFILTERED_NGL", "28")), "ngl_env": "AIOS_UNFILTERED_NGL", "ctx": 8192,
        "label": "Qwen3 8B Abliterated", "role": "Unfiltered",
        "quality": 4, "speed": "medium", "vram": "~5 GB", "ram": "~1 GB",
        "min_bytes": 4_500_000_000,
        "note": "Qwen3 8B with its refusal behaviour removed: strong at code and long questions, answers directly.",
    },

    "local-qwen3-vl-8b": {
        "dir": "qwen3-vl-8b", "ngl": int(os.environ.get("AIOS_VL_NGL", "24")), "ngl_env": "AIOS_VL_NGL", "ctx": 8192,
        "label": "Qwen3-VL 8B", "role": "Quality", "vision": True,
        "quality": 4, "speed": "medium", "vram": "~4.5 GB", "ram": "~2.5 GB",
        "note": "Sees images & video frames (Apache-2.0). Text quality of the 8B class. Partly in RAM.",
    },
}
DEFAULT_MODEL = "local-qwen3-4b"

def _discover() -> None:
    """Anything else in ~/aios/models — downloaded with praxis-models or dropped in by
    hand — becomes selectable too, labelled from its praxis-model.json when present."""
    known = {p["dir"] for p in PROFILES.values()}
    for d in sorted((HOME / "models").glob("*")):
        if not d.is_dir() or d.name in known or d.name.startswith("piper"):
            continue
        ggufs = [g for g in d.glob("*.gguf") if "mmproj" not in g.name.lower()]
        if not ggufs:
            continue
        try:
            meta = json.loads((d / "praxis-model.json").read_text())
        except (OSError, ValueError):
            meta = {}
        if "embed" in d.name or "embed" in meta.get("tags", []):
            continue                                    # embedders aren't chat models
        size_gb = max(g.stat().st_size for g in ggufs) / 1e9
        vision = bool(meta.get("vision")) or any(d.glob("mmproj*.gguf"))
        PROFILES[f"local-{d.name}"] = {
            "dir": d.name, "ngl": 99, "ctx": int(meta.get("ctx", 8192)),
            "label": meta.get("label") or d.name, "role": "Unfiltered" if meta.get("censored") is False else "Custom",
            "quality": 3, "speed": "fast" if size_gb < 3.5 else "medium",
            "vram": f"~{size_gb + 0.7:.1f} GB", "ram": "—", "vision": vision,
            "note": meta.get("desc") or "Added from ~/aios/models.",
        }

def list_models() -> list[dict]:
    _discover()
    out = []
    for mid, p in PROFILES.items():
        hits = [h for h in glob.glob(str(HOME / "models" / p["dir"] / "*.gguf")) if "mmproj" not in os.path.basename(h).lower()]
        complete = any(os.path.getsize(h) >= p.get("min_bytes", 1) for h in hits)
        out.append({
            "id": mid, "provider": "local", "paid": False,
            "label": p["label"], "role": p["role"],
            "quality": p["quality"], "speed": p["speed"],
            "vram": p["vram"], "ram": p["ram"], "ctx": p["ctx"], "vision": bool(p.get("vision")),
            "note": p["note"], "available": complete and (not p.get("vision") or bool(glob.glob(str(HOME / "models" / p["dir"] / "mmproj*.gguf")))),
        })
    return out

_fit: bool | None = None

def _supports_fit() -> bool:
    """llama.cpp builds from late 2025 on can fit the GPU offload to free memory."""
    global _fit
    if _fit is None:
        try:
            r = subprocess.run([str(BIN), "--help"], capture_output=True, text=True, timeout=15)
            _fit = "--fit" in (r.stdout + r.stderr)
        except (OSError, subprocess.SubprocessError):
            _fit = False
    return _fit

def _find_gguf(sub: str) -> str:
    hits = sorted(
        [h for h in glob.glob(str(HOME / "models" / sub / "*.gguf")) if "mmproj" not in os.path.basename(h).lower()],
        key=os.path.getsize
    )
    if not hits:
        raise FileNotFoundError(
            f"No .gguf file found in {HOME}/models/{sub}/ — model not downloaded yet"
        )
    profile = next((p for p in PROFILES.values() if p["dir"] == sub), {})
    if os.path.getsize(hits[-1]) < profile.get("min_bytes", 1):
        raise FileNotFoundError(f"Model download in {HOME}/models/{sub}/ is incomplete — wait for it to finish before loading it")
    return hits[-1]   # largest = best quality when multiple exist

class LlamaAdapter:
    id   = "local"
    paid = False

    def __init__(self):
        self._proc:      asyncio.subprocess.Process | None = None
        self._loaded:    str | None = None
        self._last_used: float = 0.0
        self._active = 0                  # requests streaming right now
        self._lock = asyncio.Lock()

    def capabilities(self) -> Capability:
        return Capability(chat=True, vision=any(p.get("vision") for p in PROFILES.values()))

    async def health(self) -> bool:
        return BIN.exists()

    async def _reaper(self):
        """Background task that unloads the model after IDLE_SEC silence.

        Never while a model is loading or a request is in flight: a long prompt
        on a laptop on battery can take more than the 30 s battery limit before
        the first token, and unloading then killed the answer half-way."""
        while True:
            await asyncio.sleep(15)
            if self._idle_expired(time.time()):
                await self._unload()

    def _idle_expired(self, now: float) -> bool:
        if not self._proc or self._active or self._lock.locked():
            return False
        limit = IDLE_SEC_BATTERY if _on_battery() else IDLE_SEC
        return now - self._last_used > limit

    async def _unload(self):
        if self._proc:
            try:
                self._proc.terminate()
                await asyncio.wait_for(self._proc.wait(), timeout=10)
            except (asyncio.TimeoutError, ProcessLookupError):
                try: self._proc.kill()
                except ProcessLookupError: pass
        self._proc, self._loaded = None, None

    async def _ensure(self, model: str):
        async with self._lock:
            if (
                self._loaded == model
                and self._proc is not None
                and self._proc.returncode is None
            ):
                return  # already running, nothing to do

            await self._unload()
            self._last_used = time.time()
            p = PROFILES[model]
            gguf = _find_gguf(p["dir"])

            args = [
                str(BIN),
                "-m", gguf,
                "--port", str(PORT),
                "--host", "127.0.0.1",
                "-c",   str(p["ctx"]),
                "--cache-type-k", "q8_0",
                "--cache-type-v", "q8_0",
                "--flash-attn", "on",
                "--parallel", "1",
                "--no-warmup",
            ]
            if _on_battery():
                args += ["-t", str(THREADS_BATTERY), "--poll", "0"]
            else:
                args += ["-t", str(THREADS)]
            if _supports_fit() and not os.environ.get(p.get("ngl_env", "")):
                args += ["-fit", "on"]                   # as many layers as this GPU's free VRAM allows
            else:
                args += ["-ngl", str(p["ngl"])]
            if p.get("vision"):
                mm = sorted(glob.glob(str(HOME / "models" / p["dir"] / "mmproj*.gguf")), key=os.path.getsize)
                if mm:
                    args += ["--mmproj", mm[0]]
            # keep what the server says (fresh file per load), so a failure can be explained
            try:
                LOG.parent.mkdir(parents=True, exist_ok=True)
                log = open(LOG, "wb")
            except OSError:
                log = None
            try:
                self._proc = await asyncio.create_subprocess_exec(
                    *args,
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=log or asyncio.subprocess.DEVNULL,
                )
            finally:
                if log:
                    log.close()                   # the child has its own copy of the fd

            # wait up to 120 s for server to be ready (8B partial offload is slower)
            async with httpx.AsyncClient() as c:
                for _ in range(240):
                    if self._proc is None:
                        raise RuntimeError(f"loading {model} was cancelled (the model was unloaded meanwhile)")
                    if self._proc.returncode is not None:
                        tail = _log_tail()
                        hint = (f"Out of GPU memory — force fewer GPU layers with {p.get('ngl_env') or 'AIOS_8B_NGL'} "
                                f"in ~/aios/config/aios.env, or pick a smaller model."
                                if "out of memory" in tail.lower() or "alloc" in tail.lower()
                                else f"Details: {LOG}")
                        raise RuntimeError(
                            f"llama-server exited with code {self._proc.returncode} while loading {model}. "
                            f"{hint}" + (f" Last output: {tail}" if tail else "")
                        )
                    try:
                        r = await c.get(f"http://127.0.0.1:{PORT}/health")
                        if r.status_code == 200:
                            self._loaded = model
                            return
                    except Exception:
                        pass
                    await asyncio.sleep(0.5)

            raise RuntimeError(
                "llama-server did not start within 120 s. "
                "Check GPU drivers and model path."
            )

    async def run(self, req: Request):
        model = req.model if req.model in PROFILES else DEFAULT_MODEL
        self._active += 1
        try:
            async for tok in self._run(model, req):
                yield tok
        finally:
            self._active -= 1
            self._last_used = time.time()

    async def _run(self, model: str, req: Request):
        await self._ensure(model)
        self._last_used = time.time()

        body = {
            "stream": True,
            "max_tokens": req.max_tokens,
            "temperature": req.temperature,
            "chat_template_kwargs": {"enable_thinking": bool(req.think)},
            "messages": [
                {"role": "system", "content": req.system},
                *attach_images(req.messages, req.images),
            ],
        }
        async with httpx.AsyncClient(timeout=httpx.Timeout(None, connect=5)) as c:
            async with c.stream(
                "POST",
                f"http://127.0.0.1:{PORT}/v1/chat/completions",
                json=body,
            ) as resp:
                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    payload = line[6:].strip()
                    if payload == "[DONE]":
                        break
                    try:
                        delta = json.loads(payload)["choices"][0]["delta"]
                        tok = delta.get("content")
                        if tok:
                            self._last_used = time.time()
                            yield tok
                    except Exception:
                        continue

    async def unload_now(self):
        await self._unload()
