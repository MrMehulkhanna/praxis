"""
Warm speech-to-text. faster-whisper 'base' (int8, CPU) takes ~2–4 s to
load; loading it per utterance was most of the voice latency. Here it is
loaded once on first use and dropped after 10 minutes idle.
"""
import asyncio, os, time

IDLE_S = int(os.environ.get("AIOS_WHISPER_IDLE", "600"))
MODEL_NAME = os.environ.get("AIOS_WHISPER_MODEL", "base")

_model = None
_last = 0.0
_lock = asyncio.Lock()

def _load():
    global _model
    from faster_whisper import WhisperModel
    _model = WhisperModel(MODEL_NAME, device="cpu", compute_type="int8")
    return _model

def _transcribe_sync(path: str) -> str:
    global _last
    m = _model or _load()
    segs, _info = m.transcribe(path, vad_filter=True, beam_size=1)
    _last = time.time()
    return " ".join(s.text.strip() for s in segs).strip()

async def transcribe(path: str) -> str:
    async with _lock:
        return await asyncio.to_thread(_transcribe_sync, path)

def loaded() -> bool:
    return _model is not None

async def reaper():
    global _model
    while True:
        await asyncio.sleep(30)
        if _model is not None and time.time() - _last > IDLE_S:
            _model = None
