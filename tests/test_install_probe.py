"""The installer's disk probe: unallocated regions from a real sfdisk -J
layout, and partition roles (EFI, Windows, recovery, Linux …)."""
import importlib.util
import pathlib

PROBE = pathlib.Path(__file__).resolve().parents[1] / "iso/airootfs/usr/local/lib/praxis/install_probe.py"
spec = importlib.util.spec_from_file_location("install_probe", PROBE)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

MIB = 1024 * 1024
# a 64 GiB disk as Windows 11 lays it out, with 40 GiB freed after C:
WIN = {"partitiontable": {"label": "gpt", "sectorsize": 512, "firstlba": 2048, "lastlba": 134217694, "partitions": [
    {"node": "/dev/vda1", "start": 2048, "size": 204800, "type": "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"},
    {"node": "/dev/vda2", "start": 206848, "size": 32768, "type": "E3C9E316-0B5C-4DB8-817D-F92DF00215AE"},
    {"node": "/dev/vda3", "start": 239616, "size": 48553984, "type": "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"},
    {"node": "/dev/vda4", "start": 132681728, "size": 1535967, "type": "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC"},
]}}


def test_free_region_between_c_and_recovery():
    free = probe.free_regions(WIN, 134217728 * 512)
    big = max(free, key=lambda f: f["size_mib"])
    assert 40 * 1024 - 2 <= big["size_mib"] <= 40 * 1024 + 2        # the 40 GiB freed after C:
    assert big["start_mib"] >= (239616 + 48553984) * 512 // MIB     # starts after C:
    assert big["end_mib"] <= 132681728 * 512 // MIB                 # ends before recovery


def test_full_disk_has_no_big_gap():
    full = {"partitiontable": {"label": "gpt", "sectorsize": 512, "firstlba": 2048, "lastlba": 1000000,
                               "partitions": [{"node": "/dev/sda1", "start": 2048, "size": 997953, "type": "x"}]}}
    assert all(f["size_mib"] < 2 for f in probe.free_regions(full, 1000034 * 512))


def test_empty_disk_is_all_free():
    free = probe.free_regions(None, 100 * 1024 * MIB)
    assert free and free[0]["size_mib"] > 100 * 1024 - 4


def role(**p):
    base = {"parttype": "", "fstype": "", "partlabel": ""}
    base.update(p)
    return probe.role_of(base, "")


def test_roles():
    assert role(parttype=probe.ESP, fstype="vfat") == "esp"
    assert role(parttype=probe.MSR) == "msr"
    assert role(parttype=probe.WIN_RECOVERY, fstype="ntfs") == "recovery"
    assert role(parttype=probe.MS_DATA, fstype="ntfs") == "windows"
    assert role(fstype="BitLocker") == "windows-encrypted"
    assert role(parttype="0fc63daf-8483-4772-8e79-3d69d8477de4", fstype="ext4") == "linux"
    assert role(fstype="swap") == "swap"
    assert role() == "empty"


def test_shrink_reasons_are_actionable(monkeypatch):
    def fake(out):
        monkeypatch.setattr(probe, "run", lambda *a, **k: (1, out, ""))
        return probe.ntfs_shrink_info("/dev/x")["reason"]
    assert "Fast Startup" in fake("The NTFS partition is hibernated")
    assert "chkdsk" in fake("ERROR: NTFS is inconsistent. Run chkdsk /f on Windows")
    assert "Disk Management" in fake("ERROR(22): Reading inode 16 failed: Invalid argument")
    monkeypatch.setattr(probe, "run", lambda *a, **k: (0, "You might resize at 5368709120 bytes or 5369 MB", ""))
    assert probe.ntfs_shrink_info("/dev/x") == {"min_mib": 5120, "reason": ""}
