"""Voice commands: natural phrasing must reach the allow-list, and nothing
outside it may run. Handlers are replaced by recorders — nothing executes.

Found by feeding Piper-spoken phrases through Whisper: "Turn the volume up."
and "Open Firefox." fell through to the AI as questions.
"""
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "voice"))
import security  # noqa: E402


@pytest.fixture
def ran(monkeypatch, tmp_path):
    calls = []
    for name in list(security.HANDLERS):
        monkeypatch.setitem(security.HANDLERS, name,
                            (lambda n: lambda m, man: calls.append(n) or f"ran {n}")(name))
    monkeypatch.setattr(security, "PENDING_FILE", tmp_path / "pending.json")
    monkeypatch.setattr(security, "AUDIT_LOG", tmp_path / "audit.jsonl")
    return calls


@pytest.mark.parametrize("said, handler", [
    ("Turn the volume up.", "volume_up"),
    ("Please turn up the volume", "volume_up"),
    ("louder", "volume_up"),
    ("Hey Praxis, lower the volume.", "volume_down"),
    ("Mute the sound.", "mute_toggle"),
    ("Set brightness to 50%.", "brightness_set"),
    ("Switch to workspace 3.", "workspace_switch"),
    ("Open Firefox.", "open_app"),
    ("Can you open the file manager please?", "open_app"),
    ("Lock the screen.", "lock_screen"),
    ("Check my battery", "status_bat"),
    ("Switch to the coding model", "model_select"),
])
def test_natural_commands_run(ran, said, handler):
    r = security.route(said)
    assert r["kind"] == "command" and ran == [handler]


@pytest.mark.parametrize("said", [
    "What is using my GPU right now?",
    "Explain how volume knobs work",
    "Reboot the router settings page for me",
])
def test_questions_are_not_commands(ran, said):
    r = security.route(said)
    assert ran == [] and r["kind"] in ("question", "refused")


def test_dangerous_actions_ask_first(ran):
    r = security.route("Restart the computer.")
    assert r["kind"] == "confirm_pending" and ran == []


def test_unlisted_apps_do_not_launch(ran):
    r = security.route("Open antigravity")
    assert ran == [] and r["kind"] != "command"


def test_normalize_strips_only_courtesy():
    assert security.normalize("Hey Praxis, could you mute please?") == "mute"
    assert security.normalize("Delete my files now") == "delete files"   # the verb survives
