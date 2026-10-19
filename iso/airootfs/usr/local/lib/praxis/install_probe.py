#!/usr/bin/env python3
"""Praxis installer — what is on this computer's disks, and where Praxis can go.

    install_probe.py            JSON for the graphical installer (run as root)
    install_probe.py --text     the same, readable

For every disk: its partitions (with a role: EFI, Windows, recovery, Linux …),
the operating systems os-prober finds, unallocated regions, and which install
options are possible — with the reason when one is not:

  alongside  shrink a Windows (NTFS) partition and install in the space freed
  free       install into unallocated space that is already there
  partition  format one existing partition (advanced)
  wipe       erase the whole disk

Nothing here writes to a disk. Shrink limits come from `ntfsresize --info`
(the smallest size the NTFS volume can be resized to) plus headroom so Windows
keeps room for updates; BitLocker, hibernated / Fast Startup and dirty volumes
are reported instead of offered.
"""
import json, os, re, subprocess, sys

MIB = 1024 * 1024
MIN_PRAXIS_MIB = 30 * 1024          # smallest install the installer allows
REC_PRAXIS_MIB = 60 * 1024          # comfortable: desktop + a couple of AI models
WIN_HEADROOM_MIB = 12 * 1024        # free space Windows keeps after shrinking (updates, pagefile)

ESP = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
MSR = "e3c9e316-0b5c-4db8-817d-f92df00215ae"
MS_DATA = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
WIN_RECOVERY = "de94bba4-06d1-4d40-a16a-bfd50179d6ac"
LINUX_FS = {"0fc63daf-8483-4772-8e79-3d69d8477de4", "4f68bce3-e8cd-4db1-96e7-fbcaf984b709",
            "933ac7e1-2eb4-4f13-b844-0e14e2aef915"}
LINUX_SWAP = "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f"


def run(cmd, timeout=60):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


def live_disk():
    rc, out, _ = run(["findmnt", "-no", "SOURCE", "/run/archiso/bootmnt"])
    src = out.strip()
    if rc != 0 or not src:
        return None
    rc, out, _ = run(["lsblk", "-no", "PKNAME", src])
    parent = out.strip().splitlines()[0] if out.strip() else ""
    return "/dev/" + parent if parent else src


def os_prober():
    """{partition path: OS name} — Windows Boot Manager is reported on the ESP."""
    found = {}
    rc, out, _ = run(["os-prober"], timeout=120)
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 2:
            dev = parts[0].split("@")[0]
            found[dev] = parts[1]
    return found


def ntfs_shrink_info(dev):
    """Smallest size this NTFS volume can be resized to, or why it can't be."""
    rc, out, err = run(["ntfsresize", "--info", "--no-progress-bar", dev], timeout=300)
    text = out + err
    m = re.search(r"You might resize at (\d+) bytes", text)
    if m:
        return {"min_mib": -(-int(m.group(1)) // MIB), "reason": ""}
    low = text.lower()
    make_room = ("Or make the room in Windows: Disk Management (Win+X) › right-click the drive › "
                 "Shrink Volume, then choose “Use free space” here.")
    if "hibernat" in low or "fast restart" in low or "fast startup" in low:
        reason = ("Windows is hibernated or uses Fast Startup. In Windows, turn off Fast Startup "
                  "(Control Panel › Power Options › Choose what the power buttons do) and shut down fully. " + make_room)
    elif "inconsistent" in low or "scheduled for check" in low or "dirty" in low or "chkdsk" in low:
        reason = ("Windows needs to check this drive first: in Windows run “chkdsk C: /f” as administrator, "
                  "answer Y and restart twice. " + make_room)
    elif "bitlocker" in low:
        reason = "This drive is encrypted with BitLocker. " + make_room
    elif "reading inode" in low or "failed to read of mft" in low:
        reason = "The resize tool can't read this Windows drive safely. " + make_room
    else:
        last = [l for l in text.strip().splitlines() if l.strip()]
        reason = "The resize tool can't use this volume" + (f" ({last[-1].strip()})" if last else "") + ". " + make_room
    return {"min_mib": None, "reason": reason}


def free_regions(disk_json, disk_size):
    """Unallocated regions ≥ 1 MiB, from sfdisk's view of the table (sectors)."""
    pt = disk_json.get("partitiontable") if disk_json else None
    if not pt:
        return [{"start_mib": 1, "end_mib": disk_size // MIB - 1, "size_mib": disk_size // MIB - 2}]
    ss = pt.get("sectorsize", 512)
    first = pt.get("firstlba", 2048)
    last = pt.get("lastlba", disk_size // ss - 34)
    used = sorted((p["start"], p["start"] + p["size"] - 1) for p in pt.get("partitions", []))
    regions, cur = [], first
    for s, e in used:
        if s > cur:
            regions.append((cur, s - 1))
        cur = max(cur, e + 1)
    if cur <= last:
        regions.append((cur, last))
    out = []
    for s, e in regions:
        # whole MiBs only, aligned like every partitioning tool does
        smib = -(-(s * ss) // MIB)
        emib = ((e + 1) * ss) // MIB
        if emib - smib >= 1:
            out.append({"start_mib": smib, "end_mib": emib, "size_mib": emib - smib})
    return out


def role_of(p, osname):
    pt = (p.get("parttype") or "").lower()
    fs = (p.get("fstype") or "").lower()
    if pt == ESP or (fs == "vfat" and "efi" in (p.get("partlabel") or "").lower()):
        return "esp"
    if pt == MSR:
        return "msr"
    if pt == WIN_RECOVERY:
        return "recovery"
    if fs == "bitlocker":
        return "windows-encrypted"
    if fs == "ntfs":
        return "windows" if pt in (MS_DATA, "0x7", "7", "") else "ntfs"
    if fs == "swap" or pt == LINUX_SWAP:
        return "swap"
    if pt in LINUX_FS or fs in ("ext4", "ext3", "btrfs", "xfs", "f2fs"):
        return "linux"
    if fs in ("vfat", "exfat"):
        return "data"
    return "unknown" if fs else "empty"


def probe():
    rc, out, _ = run(["lsblk", "-J", "-b", "-o",
                      "NAME,PATH,TYPE,SIZE,MODEL,TRAN,RM,RO,FSTYPE,LABEL,PARTTYPE,PARTLABEL,PARTN,MOUNTPOINTS,PTTYPE,START,PKNAME"])
    devices = json.loads(out).get("blockdevices", []) if rc == 0 else []
    live = live_disk()
    oses = os_prober()
    disks = []
    for d in devices:
        if d.get("type") != "disk" or d.get("ro") or d["name"].startswith(("loop", "zram", "sr", "fd")):
            continue
        size = int(d.get("size") or 0)
        if size < 8 * 1024 * MIB:                 # cards, tiny sticks
            continue
        rc, sj, _ = run(["sfdisk", "-J", d["path"]])
        table = json.loads(sj) if rc == 0 and sj.strip() else None
        label = (table or {}).get("partitiontable", {}).get("label") or d.get("pttype")
        parts = []
        sect = (table or {}).get("partitiontable", {}).get("sectorsize", 512)
        tparts = {p["node"]: p for p in (table or {}).get("partitiontable", {}).get("partitions", [])}
        for c in d.get("children") or []:
            if c.get("type") != "part":
                continue
            tp = tparts.get(c["path"], {})
            start = int(tp.get("start", c.get("start") or 0)) * sect
            psize = int(tp.get("size", 0)) * sect or int(c.get("size") or 0)
            mounts = [m for m in (c.get("mountpoints") or []) if m]
            osname = oses.get(c["path"], "")
            p = {
                "path": c["path"], "num": int(c.get("partn") or 0),
                "start_mib": start // MIB, "size_mib": psize // MIB, "end_mib": (start + psize) // MIB,
                "fstype": c.get("fstype") or "", "label": c.get("label") or "", "partlabel": c.get("partlabel") or "",
                "parttype": (c.get("parttype") or "").lower(), "mounted": mounts, "os": osname,
            }
            p["role"] = role_of(p, osname)
            if p["role"] == "windows" and p["size_mib"] >= MIN_PRAXIS_MIB + WIN_HEADROOM_MIB:
                info = ntfs_shrink_info(c["path"]) if not mounts else {"min_mib": None, "reason": "mounted"}
                if info["min_mib"] is not None:
                    keep = info["min_mib"] + max(WIN_HEADROOM_MIB, p["size_mib"] // 10)
                    can_give = p["size_mib"] - keep
                    p["shrink"] = {"min_fs_mib": info["min_mib"], "keep_mib": keep,
                                   "max_praxis_mib": max(0, can_give), "reason": ""
                                   if can_give >= MIN_PRAXIS_MIB else
                                   f"only {max(0, can_give) // 1024} GiB could be freed — Praxis needs {MIN_PRAXIS_MIB // 1024} GiB. Free up space in Windows first."}
                elif info["reason"] == "mounted":
                    p["shrink"] = {"max_praxis_mib": 0, "reason": "It's open in the live session — it will be closed first; scan again."}
                else:
                    p["shrink"] = {"max_praxis_mib": 0, "reason": info["reason"]}
            parts.append(p)
        free = free_regions(table, size) if label else [{"start_mib": 1, "end_mib": size // MIB - 1, "size_mib": size // MIB - 2}]
        largest = max((f["size_mib"] for f in free), default=0)
        esp = next((p["path"] for p in parts if p["role"] == "esp"), None)
        is_live = live is not None and d["path"] == live
        has_windows = any(p["role"] in ("windows", "windows-encrypted") for p in parts) or any(
            "windows" in (p["os"] or "").lower() for p in parts)

        opts = {}
        # alongside: shrink the NTFS partition that can give the most
        cands = [p for p in parts if p.get("shrink")]
        best = max(cands, key=lambda p: p["shrink"].get("max_praxis_mib", 0), default=None)
        if label == "dos" and has_windows:
            opts["alongside"] = {"possible": False, "reason": "Windows on this disk starts in legacy BIOS mode; Praxis needs UEFI. Use a disk with a GPT table."}
        elif best and best["shrink"]["max_praxis_mib"] >= MIN_PRAXIS_MIB:
            mx = best["shrink"]["max_praxis_mib"]
            opts["alongside"] = {"possible": True, "part": best["path"], "part_size_mib": best["size_mib"],
                                 "min_praxis_mib": MIN_PRAXIS_MIB, "max_praxis_mib": mx,
                                 "default_praxis_mib": max(min(mx, REC_PRAXIS_MIB), min(mx, mx // 2)),
                                 "reason": ""}
        elif best:
            opts["alongside"] = {"possible": False, "part": best["path"], "reason": best["shrink"]["reason"]}
        elif any(p["role"] == "windows-encrypted" for p in parts):
            opts["alongside"] = {"possible": False, "reason": "Windows is encrypted with BitLocker. Suspend BitLocker (or turn off Device encryption) in Windows, or make free space in Disk Management, then try again."}
        elif any(p["role"] == "windows" for p in parts):
            small = max((p for p in parts if p["role"] == "windows"), key=lambda p: p["size_mib"])
            opts["alongside"] = {"possible": False, "part": small["path"],
                                 "reason": f"Windows' drive is {small['size_mib'] // 1024} GiB — too small to give Praxis {MIN_PRAXIS_MIB // 1024} GiB and keep room for Windows"}
        else:
            opts["alongside"] = {"possible": False, "reason": "no Windows partition to make room in"}
        opts["free"] = ({"possible": True, "size_mib": largest} if largest >= MIN_PRAXIS_MIB and label else
                        {"possible": False, "size_mib": largest,
                         "reason": f"{largest // 1024} GiB unallocated — Praxis needs {MIN_PRAXIS_MIB // 1024} GiB"})
        cands = [p["path"] for p in parts if p["role"] in ("linux", "empty", "unknown", "data")
                 and p["size_mib"] >= 20 * 1024 and not p["mounted"]]
        opts["partition"] = {"possible": bool(cands) and bool(esp), "candidates": cands,
                             "reason": "" if cands and esp else ("no EFI partition on this disk" if cands else "no suitable partition (≥ 20 GiB, not Windows or EFI)")}
        opts["wipe"] = {"possible": not is_live, "reason": "this is the USB drive Praxis is running from" if is_live else ""}
        if is_live:
            for k in opts:
                opts[k] = {"possible": False, "reason": "this is the USB drive Praxis is running from"}

        disks.append({
            "path": d["path"], "model": (d.get("model") or "").strip() or "Disk", "tran": d.get("tran") or "",
            "removable": bool(d.get("rm")), "size_mib": size // MIB, "label": label, "is_live": is_live,
            "esp": esp, "has_windows": has_windows, "partitions": parts, "free": free,
            "largest_free_mib": largest, "options": opts,
        })
    mem = 0
    try:
        mem = int(next(l.split()[1] for l in open("/proc/meminfo") if l.startswith("MemTotal"))) // 1024
    except (OSError, StopIteration, ValueError):
        pass
    return {"uefi": os.path.isdir("/sys/firmware/efi"), "live_disk": live, "ram_mib": mem,
            "min_praxis_mib": MIN_PRAXIS_MIB, "disks": disks}


def text(info):
    print(f"UEFI: {'yes' if info['uefi'] else 'NO — Praxis needs UEFI'}   RAM: {info['ram_mib'] // 1024} GiB")
    for d in info["disks"]:
        print(f"\n{d['path']}  {d['model']}  {d['size_mib'] / 1024:.0f} GiB  ({d['label'] or 'no partition table'})"
              + ("  [live USB]" if d["is_live"] else ""))
        for p in d["partitions"]:
            extra = f"  {p['os']}" if p["os"] else ""
            if p.get("shrink"):
                s = p["shrink"]
                extra += (f"  can give up to {s['max_praxis_mib'] // 1024} GiB" if not s["reason"] else f"  (no shrink: {s['reason']})")
            print(f"  {p['path']:<16} {p['size_mib'] / 1024:>8.1f} GiB  {p['fstype'] or '-':<9} {p['role']:<17}{extra}")
        for f in d["free"]:
            if f["size_mib"] >= 1024:
                print(f"  {'(unallocated)':<16} {f['size_mib'] / 1024:>8.1f} GiB")
        for k, o in d["options"].items():
            print(f"    {k:<10} {'yes' if o.get('possible') else 'no '}  {o.get('reason', '')}")


if __name__ == "__main__":
    info = probe()
    if "--text" in sys.argv:
        text(info)
    else:
        json.dump(info, sys.stdout, indent=1)
        print()
