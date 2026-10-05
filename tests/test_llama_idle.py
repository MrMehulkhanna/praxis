"""The idle reaper must never unload a model that is loading or answering.

It used to compare against a timestamp that was only set after loading had
finished, so a 15 s reaper tick during a load (or during a long prompt on
battery, where the limit is 30 s) killed llama-server mid-request."""
import asyncio

from adapters.local import llama


def _adapter(last_used=0.0):
    a = llama.LlamaAdapter()
    a._proc = object()            # stands in for a running llama-server
    a._last_used = last_used
    return a


def test_idle_model_is_unloaded(monkeypatch):
    monkeypatch.setattr(llama, "_on_battery", lambda: False)
    assert _adapter()._idle_expired(now=10_000)


def test_recently_used_model_stays(monkeypatch):
    monkeypatch.setattr(llama, "_on_battery", lambda: False)
    assert not _adapter(last_used=9_990)._idle_expired(now=10_000)


def test_busy_model_is_never_unloaded(monkeypatch):
    monkeypatch.setattr(llama, "_on_battery", lambda: True)
    a = _adapter()
    a._active = 1                 # an answer is streaming (or waiting for its first token)
    assert not a._idle_expired(now=10_000)


def test_loading_model_is_never_unloaded(monkeypatch):
    monkeypatch.setattr(llama, "_on_battery", lambda: True)
    a = _adapter()

    async def check():
        async with a._lock:       # _ensure() holds the lock while llama-server loads
            return a._idle_expired(now=10_000)

    assert asyncio.run(check()) is False


def test_battery_unloads_sooner(monkeypatch):
    monkeypatch.setattr(llama, "_on_battery", lambda: True)
    now = 10_000
    a = _adapter(last_used=now - llama.IDLE_SEC_BATTERY - 1)
    assert a._idle_expired(now)
    monkeypatch.setattr(llama, "_on_battery", lambda: False)
    assert not a._idle_expired(now)
