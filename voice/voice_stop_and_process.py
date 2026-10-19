#!/usr/bin/env python3
"""
voice_stop_and_process.py (v2) — same pipeline as before, now routes every
transcript through security.route() instead of the old direct-execution
voice_router.route(). Replaces the previous version — delete voice_router.py
after this is installed, security.py supersedes it entirely.

Pipeline:
  stop pw-record -> faster-whisper transcribe -> security.route()
    -> "command"         : already executed by security.py, speak result
    -> "confirm_pending"  : NOT executed yet, speak the confirmation prompt
    -> "refused"          : NOT executed, speak the refusal
    -> "question"         : forward to AIOS /api/chat, speak the answer
"""
import json, os, signal, subprocess, sys, time, pathlib
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from security import route
from voice_speak import speak

WAV = "/tmp/aios-voice.wav"
PIDFILE = "/tmp/aios-voice.pid"
AIOS_URL = "http://127.0.0.1:8778/api/agent"   # agent: gathers evidence for system questions
STT_URL  = "http://127.0.0.1:8778/api/voice/transcribe"
DEFAULT_MODEL = "auto"   # server resolves to the one model selected everywhere

def stop_recording():
    if not os.path.exists(PIDFILE):
        return
    pid = int(open(PIDFILE).read().strip())
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    os.remove(PIDFILE)
    time.sleep(0.3)

def transcribe(path: str) -> str:
    # warm whisper inside the backend (no per-utterance model load); local fallback if it is down
    try:
        req = urllib.request.Request(STT_URL, data=json.dumps({"path": path}).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read()).get("text", "").strip()
    except Exception:
        from faster_whisper import WhisperModel
        model = WhisperModel("base", device="cpu", compute_type="int8")
        segments, _info = model.transcribe(path, vad_filter=True)
        return " ".join(seg.text.strip() for seg in segments).strip()

def ask_aios(question: str, model: str = DEFAULT_MODEL) -> str:
    body = json.dumps({
        "message": question,
        "conversation_id": "voice-session",
        "model": model,
    }).encode()
    req = urllib.request.Request(
        AIOS_URL, data=body, headers={"Content-Type": "application/json"},
    )
    out = []
    try:
        with urllib.request.urlopen(req, timeout=None) as resp:
            event = "message"
            for raw in resp:
                line = raw.decode().rstrip("\n")
                if line.startswith("event: "):
                    event = line[7:].strip()
                    continue
                if not line.startswith("data: "):
                    continue
                data = line[6:]
                # SSE event types apply to one data field only; reset after
                # use or every token after "meta" is silently dropped.
                this_event, event = event, "message"
                if data == "{}":
                    continue
                if this_event == "pending":
                    p = json.loads(data)
                    out.append(f" I can run: {p.get('cmd')} — confirm it in the AI panel.")
                elif this_event not in ("meta", "error", "done", "step", "jobs"):
                    out.append(json.loads(data))
    except Exception as e:
        return f"I couldn't reach AIOS: {e}"
    return "".join(out).strip() or "No response."

def main():
    stop_recording()

    if not os.path.exists(WAV):
        print(json.dumps({"transcript": "", "kind": "empty",
                          "reply": "No audio captured", "spoken": False}))
        return

    transcript = transcribe(WAV)
    os.remove(WAV)

    if not transcript:
        print(json.dumps({"transcript": "", "kind": "empty",
                          "reply": "Didn't catch that", "spoken": False}))
        return

    result = route(transcript)   # <-- security gate; may or may not execute

    if result["kind"] == "question":
        answer = ask_aios(transcript)
        result["reply"] = answer
        speak(answer)
        spoken = True
    elif result.get("spoken"):
        speak(result["spoken"])
        spoken = True
    else:
        spoken = False

    print(json.dumps({
        "transcript": transcript,
        "kind": result["kind"],
        "reply": result["reply"],
        "executed": result.get("executed", False),
        "spoken": spoken,
    }))

if __name__ == "__main__":
    main()
