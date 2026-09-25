#!/usr/bin/env python3
"""
voice_speak.py — text-to-speech via Piper, played through PipeWire.

Requires:
  - `piper` binary on PATH (see README — this is the one piece not yet
    installed by the earlier setup scripts; only the voice *model* was
    downloaded, not the binary)
  - the amy-low voice model at ~/aios/models/piper-amy/*.onnx
    (already fetched by 02-download-models.sh)

Uses pw-cat (ships with pipewire, same package that provides pw-record,
already on your system) rather than aplay, to avoid ALSA/PipeWire conflicts.
"""
import subprocess, sys, os, pathlib, glob

AIOS_HOME = pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))

def _find_model():
    hits = glob.glob(str(AIOS_HOME / "models" / "piper-amy" / "**" / "*.onnx"), recursive=True)
    return hits[0] if hits else None

def speak(text: str):
    text = text.strip()
    if not text:
        return
    model = _find_model()
    if not model:
        print(f"[voice_speak] no piper model under {AIOS_HOME}/models/piper-amy/", file=sys.stderr)
        return
    if subprocess.call(["which", "piper"], stdout=subprocess.DEVNULL) != 0:
        print("[voice_speak] `piper` binary not on PATH — see README install step", file=sys.stderr)
        return

    # cap length so a long AIOS answer doesn't turn into a two-minute
    # TTS monologue — speak a summary-length excerpt, not the whole thing
    if len(text) > 400:
        text = text[:400].rsplit(".", 1)[0] + "."

    piper = subprocess.Popen(
        ["piper", "--model", model, "--output-raw"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    )
    play = subprocess.Popen(
        ["pw-cat", "--playback", "--raw",
         "--channels=1", "--rate=22050", "--format=s16", "-"],
        stdin=piper.stdout,
    )
    piper.stdin.write(text.encode())
    piper.stdin.close()
    play.wait()

if __name__ == "__main__":
    speak(" ".join(sys.argv[1:]))
