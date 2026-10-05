"""Voice typing: spoken layout commands become characters, and only an
explicit "press enter" at the very end sends the text."""
import importlib.machinery
import importlib.util
import pathlib

import pytest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "iso/airootfs/usr/local/bin/praxis-dictate"


@pytest.fixture(scope="module")
def pd():
    loader = importlib.machinery.SourceFileLoader("praxis_dictate", str(SCRIPT))
    spec = importlib.util.spec_from_loader("praxis_dictate", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


@pytest.mark.parametrize("heard, text, enter", [
    ("Please list files. New line. Then press Enter.", "Please list files.\nThen", True),
    ("Hello world. New paragraph. Second part", "Hello world.\n\nSecond part", False),
    ("git status, press enter.", "git status", True),
    ("Enter the room", "Enter the room", False),          # "enter" mid-sentence is just a word
    ("Type newline here", "Type\nhere", False),
    ("Hit enter", "", True),
    ("I will press enter later", "I will press enter later", False),
])
def test_shape(pd, heard, text, enter):
    assert pd.shape(heard) == (text, enter)


def test_silence_phrases_are_ignored(pd):
    assert "thank you." in pd.NOISE and "" in pd.NOISE
