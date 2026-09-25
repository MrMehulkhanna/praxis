"""
Local llama-server adapter.

Starts llama-server on demand with CUDA offload (sm_89 = RTX 4050, 6 GB).
Auto-unloads after idle — this is what keeps Hyprland smooth.

KV cache at q8_0 = half the VRAM of fp16 cache.
Flash attention on = faster, lower VRAM for long contexts.
"""
import asyncio, glob, json, os, pathlib, time
import httpx
from core.gateway.iface import Capability, Request, attach_images

HOME     = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))
BIN      = HOME / "llama-server"
PORT     = int(os.environ.get("LLAMA_PORT", "8779"))
IDLE_SEC = int(os.environ.get("AIOS_IDLE_UNLOAD", "120"))

# ── model registry ───────────────────────────────────────────────────────
# ngl = layers on GPU. 99 = everything. The 8B model does not fit fully in
# 6 GB next to a compositor, so it splits: ~28 layers on GPU, the rest in
# system RAM (16 GB). Slower per token, noticeably better answers.
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
        "dir": "qwen3-8b", "ngl": int(os.environ.get("AIOS_8B_NGL", "28")), "ctx": 6144,
        "label": "Qwen3 8B", "role": "Quality",
        "quality": 4, "speed": "medium", "vram": "~4.2 GB", "ram": "~2 GB",
        "note": "Highest-quality local option. Partly in RAM → medium reply time.",
    },
    "local-dolphin-v2-8b": {
        "dir": "dolphin-v2-8b-abliterated", "ngl": int(os.environ.get("AIOS_DOLPHIN_NGL", "24")), "ctx": 4096,
        "label": "Dolphin V2 8B", "role": "Quality",
        "quality": 4, "speed": "medium", "vram": "~4.7 GB", "ram": "~2.5 GB",
        "min_bytes": 4_500_000_000,
        "note": "Unfiltered Qwen3-8B derivative. Partly offloaded to preserve 6 GB GPU desktop headroom.",
    },

    "local-qwen3-vl-8b": {
        "dir": "qwen3-vl-8b", "ngl": int(os.environ.get("AIOS_VL_NGL", "24")), "ctx": 8192,
        "label": "Qwen3-VL 8B", "role": "Quality", "vision": True,
        "quality": 4, "speed": "medium", "vram": "~4.5 GB", "ram": "~2.5 GB",
        "note": "Sees images & video frames (Apache-2.0). Text quality of the 8B class. Partly in RAM.",
    },
}
DEFAULT_MODEL = "local-qwen3-4b"

def list_models() -> list[dict]:
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
        self._lock = asyncio.Lock()

    def capabilities(self) -> Capability:
        return Capability(chat=True, vision=any(p.get("vision") for p in PROFILES.values()))

    async def health(self) -> bool:
        return BIN.exists()

    async def _reaper(self):
        """Background task that unloads the model after IDLE_SEC silence."""
        while True:
            await asyncio.sleep(15)
            if self._proc and time.time() - self._last_used > IDLE_SEC:
                await self._unload()

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
            p = PROFILES[model]
            gguf = _find_gguf(p["dir"])

            args = [
                str(BIN),
                "-m", gguf,
                "--port", str(PORT),
                "--host", "127.0.0.1",
                "-ngl", str(p["ngl"]),
                "-c",   str(p["ctx"]),
                "--cache-type-k", "q8_0",
                "--cache-type-v", "q8_0",
                "--flash-attn", "on",
                "-t", "6",          # 12 physical cores; leave headroom for the desktop
                "--parallel", "1",
                "--no-warmup",
            ]
            if p.get("vision"):
                mm = sorted(glob.glob(str(HOME / "models" / p["dir"] / "mmproj*.gguf")), key=os.path.getsize)
                if mm:
                    args += ["--mmproj", mm[0]]
            self._proc = await asyncio.create_subprocess_exec(
                *args,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )

            # wait up to 120 s for server to be ready (8B partial offload is slower)
            async with httpx.AsyncClient() as c:
                for _ in range(240):
                    if self._proc.returncode is not None:
                        raise RuntimeError(
                            f"llama-server exited with code {self._proc.returncode} "
                            f"while loading {model} — likely out of VRAM. "
                            f"Lower AIOS_8B_NGL in ~/aios/config/aios.env."
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
