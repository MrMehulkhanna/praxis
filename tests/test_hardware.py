"""GPU mode (ASUS MUX) and NVIDIA sleep detection, against a fake /sys.

The MUX label was once inverted (0 shown as "hybrid"), which told the user
their laptop was in hybrid mode while the NVIDIA GPU drew every pixel.
"""
from core import hardware


def fake_sys(monkeypatch, files: dict, dirs: dict):
    monkeypatch.setattr(hardware, "_read", lambda p, default="": files.get(p, default))
    monkeypatch.setattr(hardware.glob, "glob", lambda pattern: dirs.get(pattern, []))
    monkeypatch.setattr(hardware.os.path, "exists", lambda p: p in files)


NV = "/sys/bus/pci/devices/0000:01:00.0"
IGPU = "/sys/bus/pci/devices/0000:00:02.0"
PCI = {"/sys/bus/pci/devices/*": [IGPU, NV]}
BASE = {f"{NV}/vendor": "0x10de", f"{NV}/class": "0x030000",
        f"{IGPU}/vendor": "0x8086", f"{IGPU}/class": "0x038000"}


def test_mux_0_is_discrete(monkeypatch):
    fake_sys(monkeypatch, {hardware.SYS_MUX: "0"}, {})
    m = hardware.mux()
    assert m["supported"] and m["label"] == "dGPU only"


def test_mux_1_is_hybrid(monkeypatch):
    fake_sys(monkeypatch, {hardware.SYS_MUX: "1", hardware.SYS_PENDING: "1"}, {})
    m = hardware.mux()
    assert m["label"] == "hybrid (iGPU + dGPU)" and m["pending_reboot"]


def test_no_mux_is_unsupported(monkeypatch):
    fake_sys(monkeypatch, {}, {})
    assert hardware.mux()["supported"] is False
    ok, msg = hardware.set_gpu_mux("hybrid")
    assert not ok and "no switchable" in msg


def test_bad_mode_is_refused(monkeypatch):
    fake_sys(monkeypatch, {hardware.SYS_MUX: "0"}, {})
    ok, msg = hardware.set_gpu_mux("turbo")
    assert not ok and "hybrid or dgpu" in msg


def test_display_gpu_follows_the_panel(monkeypatch):
    conn = "/sys/class/drm/card2-eDP-1"
    fake_sys(monkeypatch, {f"{conn}/status": "connected", "/sys/class/drm/card2/device/vendor": "0x10de"},
             {"/sys/class/drm/card*-eDP-*": [conn]})
    assert hardware.display_gpu() == "nvidia"


def test_sleeping_nvidia_is_not_woken(monkeypatch):
    fake_sys(monkeypatch, {**BASE, f"{NV}/power/runtime_status": "suspended"}, PCI)
    monkeypatch.setattr(hardware.shutil, "which", lambda name: "/usr/bin/" + name)
    monkeypatch.setattr(hardware, "_run", lambda *a, **k: (_ for _ in ()).throw(AssertionError("nvidia-smi called")))
    g = hardware.gpu()
    assert g["asleep"] and g["util"] == 0.0


def test_awake_nvidia_is_queried(monkeypatch):
    fake_sys(monkeypatch, {**BASE, f"{NV}/power/runtime_status": "active"}, PCI)
    assert hardware.nvidia_asleep() is False
