"""
Hardware view + the few safe controls a laptop exposes — whatever this
machine actually has (anything missing is reported absent, not faked).

Reads: /sys (coretemp, hwmon fans, battery, platform_profile, LED keyboard
backlights, asus-armoury), nvidia-smi (only while that GPU is awake), /proc.
Writes that need root go through pkexec so the user always sees an auth
prompt — nothing silent.
"""
import glob, os, pathlib, re, shutil, subprocess, time

SYS_PROFILE  = "/sys/firmware/acpi/platform_profile"
SYS_CHOICES  = "/sys/firmware/acpi/platform_profile_choices"
SYS_MUX      = "/sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value"
SYS_MUX_OLD  = "/sys/devices/platform/asus-nb-wmi/gpu_mux_mode"
SYS_PENDING  = "/sys/class/firmware-attributes/asus-armoury/attributes/pending_reboot"
# asus-wmi ABI: 0 = discrete (the NVIDIA GPU drives the screens), 1 = Optimus/hybrid
MUX_LABELS   = {"0": "dGPU only", "1": "hybrid (iGPU + dGPU)"}
# the firmware keeps reporting the active mode until the restart; remember what was asked
MUX_REQUEST  = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "praxis-gpu-mux-requested")
HW_HELPER    = "/usr/local/libexec/aios-hardware"

def _read(p: str, default: str = "") -> str:
    try:
        return pathlib.Path(p).read_text().strip()
    except OSError:
        return default

def _run(cmd: list[str], timeout: float = 4) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""

def _hwmon(name: str) -> str | None:
    for d in glob.glob("/sys/class/hwmon/hwmon*"):
        if _read(f"{d}/name") == name:
            return d
    return None

_prev_cpu: tuple | None = None
_prev_net: tuple | None = None

def cpu() -> dict:
    global _prev_cpu
    stat = _read("/proc/stat").split("\n")[0].split()[1:]
    vals = list(map(int, stat)); idle = vals[3] + vals[4]; total = sum(vals)
    usage = 0.0
    if _prev_cpu:
        dt, di = total - _prev_cpu[0], idle - _prev_cpu[1]
        usage = round(100 * (1 - di / dt), 1) if dt > 0 else 0.0
    _prev_cpu = (total, idle)
    core = _hwmon("coretemp")
    temp = int(_read(f"{core}/temp1_input", "0")) // 1000 if core else None
    model = ""
    for line in _read("/proc/cpuinfo").split("\n"):
        if line.startswith("model name"):
            model = line.split(":", 1)[1].strip(); break
    freqs = [int(f) for f in (_read(p) for p in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")) if f.isdigit()]
    load = _read("/proc/loadavg").split()[:3]
    return {"model": model, "usage": usage, "temp_c": temp,
            "freq_mhz": int(sum(freqs) / len(freqs) / 1000) if freqs else None,
            "cores": os.cpu_count(), "load": [float(x) for x in load],
            "governor": _read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")}

def memory() -> dict:
    m = {}
    for line in _read("/proc/meminfo").split("\n"):
        k, _, v = line.partition(":")
        if k in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
            m[k] = int(v.split()[0]) * 1024
    used = m.get("MemTotal", 0) - m.get("MemAvailable", 0)
    return {"total": m.get("MemTotal", 0), "used": used, "available": m.get("MemAvailable", 0),
            "percent": round(100 * used / m["MemTotal"], 1) if m.get("MemTotal") else 0,
            "swap_total": m.get("SwapTotal", 0), "swap_used": m.get("SwapTotal", 0) - m.get("SwapFree", 0)}

def _nvidia_dev() -> str | None:
    for d in glob.glob("/sys/bus/pci/devices/*"):
        if _read(f"{d}/vendor") == "0x10de" and _read(f"{d}/class").startswith("0x03"):
            return d
    return None

def nvidia_asleep() -> bool:
    """True while the NVIDIA GPU is runtime-suspended. Any nvidia-smi query would
    wake it (and keep it up for its autosuspend delay), so statistics must not ask."""
    d = _nvidia_dev()
    return bool(d) and _read(f"{d}/power/runtime_status") == "suspended"

def display_gpu() -> str:
    """Which GPU drives the built-in screen: the card owning the connected eDP/LVDS."""
    for c in glob.glob("/sys/class/drm/card*-eDP-*") + glob.glob("/sys/class/drm/card*-LVDS-*"):
        if _read(f"{c}/status") == "connected":
            card = os.path.basename(c).split("-", 1)[0]          # card2-eDP-1 -> card2
            v = _read(f"/sys/class/drm/{card}/device/vendor")
            return {"0x10de": "nvidia", "0x8086": "intel", "0x1002": "amd"}.get(v, v)
    return ""

def mux() -> dict:
    raw = _read(SYS_MUX) or _read(SYS_MUX_OLD)
    pending = _read(SYS_PENDING) == "1"
    requested = (_read(MUX_REQUEST) if pending else "") or raw
    return {"supported": raw in MUX_LABELS, "value": raw, "label": MUX_LABELS.get(raw, "unknown"),
            "pending_reboot": pending, "requested": requested, "display_gpu": display_gpu()}

_PCI_IDS = ("/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids")

def _pci_name(vendor: str, device: str) -> str:
    """Product name from the pci.ids database — never touches the device, so it
    can't wake a sleeping GPU the way lspci or nvidia-smi would."""
    v, d = vendor.lower().removeprefix("0x"), device.lower().removeprefix("0x")
    for path in _PCI_IDS:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                in_vendor = False
                for line in f:
                    if not line.strip() or line.startswith("#"):
                        continue
                    if not line.startswith("\t"):
                        if in_vendor:
                            break
                        in_vendor = line.startswith(v + "  ")
                    elif in_vendor and line.startswith("\t" + d + "  "):
                        return line.strip()[len(d):].strip()
        except OSError:
            continue
    return ""

def gpus() -> list[str]:
    """Every display adapter, e.g. ['Intel Iris Xe Graphics', 'NVIDIA GeForce RTX 4050 Max-Q / Mobile']."""
    out = []
    for d in sorted(glob.glob("/sys/bus/pci/devices/*")):
        if not _read(f"{d}/class").startswith("0x03"):
            continue
        vendor = _read(f"{d}/vendor")
        brand = {"0x10de": "NVIDIA", "0x8086": "Intel", "0x1002": "AMD"}.get(vendor, "")
        name = _pci_name(vendor, _read(f"{d}/device"))
        m = re.search(r"\[(.+?)\]", name)          # 'AD107M [GeForce RTX 4050 …]' → the bracketed name
        out.append(f"{brand} {m.group(1) if m else name}".strip() or "unknown GPU")
    return out

def gpu() -> dict:
    m = mux()
    extra = {"mux_mode": m["label"], "mux": m}
    if not shutil.which("nvidia-smi"):
        return {"present": False, **extra}
    if nvidia_asleep():
        return {"present": True, "asleep": True, "util": 0.0, "power_w": 0.0, "processes": [], **extra}
    out = _run(["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.gr,pstate",
                "--format=csv,noheader,nounits"])
    if not out:
        return {"present": True, "error": "nvidia-smi returned nothing (driver not loaded)", **extra}
    p = [x.strip() for x in out.split(",")]
    f = lambda x: float(x) if re.match(r"^-?\d+(\.\d+)?$", x) else None
    procs = _run(["nvidia-smi", "--query-compute-apps=pid,process_name,used_memory", "--format=csv,noheader,nounits"])
    return {"present": True, "name": p[0], "util": f(p[1]), "vram_used_mb": f(p[2]), "vram_total_mb": f(p[3]),
            "temp_c": f(p[4]), "power_w": f(p[5]), "power_limit_w": f(p[6]), "clock_mhz": f(p[7]), "pstate": p[8],
            **extra,
            "processes": [dict(zip(("pid", "name", "vram_mb"), [s.strip() for s in l.split(",")])) for l in procs.split("\n") if l.strip()]}

def storage() -> list[dict]:
    rows = []
    for line in _run(["df", "-B1", "--output=target,fstype,size,used,avail,pcent", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs"]).split("\n")[1:]:
        p = line.split()
        if len(p) == 6 and p[0].startswith("/"):
            rows.append({"mount": p[0], "fs": p[1], "size": int(p[2]), "used": int(p[3]), "avail": int(p[4]), "percent": int(p[5].rstrip("%"))})
    nvme = _hwmon("nvme")
    return {"filesystems": rows, "nvme_temp_c": int(_read(f"{nvme}/temp1_input", "0")) // 1000 if nvme else None}

def battery() -> dict:
    b = glob.glob("/sys/class/power_supply/BAT*")
    if not b:
        return {"present": False}
    b = b[0]
    en, ef, ed = (int(_read(f"{b}/{k}", "0")) for k in ("energy_now", "energy_full", "energy_full_design"))
    return {"present": True, "percent": int(_read(f"{b}/capacity", "0")), "status": _read(f"{b}/status"),
            "health_percent": round(100 * ef / ed, 1) if ed else None,
            "power_w": round(int(_read(f"{b}/power_now", "0")) / 1e6, 1),
            "charge_limit": int(_read(f"{b}/charge_control_end_threshold", "100") or 100),
            "charge_limit_supported": os.path.exists(f"{b}/charge_control_end_threshold"),
            "cycle_count": _read(f"{b}/cycle_count", "?"),
            "ac": any(_read(f"{p}/online") == "1" for p in glob.glob("/sys/class/power_supply/*")
                      if _read(f"{p}/type") in ("Mains", "USB"))}

def fans() -> dict:
    a = _hwmon("asus")
    if not a:
        return {"present": False, "note": "no asus hwmon fan interface"}
    mode = _read(f"{a}/pwm1_enable")
    return {"present": True, "rpm": int(_read(f"{a}/fan1_input", "0")),
            "mode": {"0": "full", "2": "auto"}.get(mode, mode),
            "curves": False, "control_ready": False,
            "note": "The firmware exposes fan telemetry only; cooling follows the thermal profile."}

def platform_profile() -> dict:
    return {"current": _read(SYS_PROFILE), "choices": _read(SYS_CHOICES).split(),
            "daemon": _run(["powerprofilesctl", "get"])}

def _kbd_dev() -> str | None:
    """asus::kbd_backlight, dell::kbd_backlight, tpacpi::kbd_backlight, …"""
    devs = sorted(glob.glob("/sys/class/leds/*::kbd_backlight"))
    return os.path.basename(devs[0]) if devs else None

def keyboard_backlight() -> dict:
    dev = _kbd_dev()
    out = _run(["brightnessctl", "-d", dev, "-m"]) if dev else ""
    if not out:
        return {"present": False}
    p = out.split(",")
    return {"present": True, "level": int(p[2]), "max": int(p[4]), "device": dev}

def temps() -> dict:
    t = {}
    for name, key in (("coretemp", "cpu"), ("nvme", "nvme"), ("acpitz", "board"), ("iwlwifi_1", "wifi")):
        d = _hwmon(name)
        if d:
            v = _read(f"{d}/temp1_input", "")
            if v.isdigit():
                t[key] = int(v) // 1000
    g = gpu()
    if g.get("temp_c") is not None:
        t["gpu"] = int(g["temp_c"])
    return t

def network() -> dict:
    global _prev_net
    rx = tx = 0
    for line in _read("/proc/net/dev").split("\n")[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        if name == "lo" or not rest:
            continue
        f = rest.split()
        rx += int(f[0]); tx += int(f[8])
    now = time.time()
    down = up = 0.0
    if _prev_net:
        dt = now - _prev_net[0]
        if dt > 0:
            down = (rx - _prev_net[1]) / dt; up = (tx - _prev_net[2]) / dt
    _prev_net = (now, rx, tx)
    return {"rx_bytes": rx, "tx_bytes": tx, "down_bps": int(down), "up_bps": int(up)}

def snapshot() -> dict:
    return {"cpu": cpu(), "memory": memory(), "gpu": gpu(), "storage": storage(), "battery": battery(),
            "fans": fans(), "profile": platform_profile(), "keyboard": keyboard_backlight(),
            "temps": temps(), "network": network(),
            "model": f"{_read('/sys/class/dmi/id/sys_vendor')} {_read('/sys/class/dmi/id/product_name')}",
            "kernel": os.uname().release, "uptime_s": int(float(_read("/proc/uptime", "0").split()[0]))}

# ── controls ───────────────────────────────────────────────────────────
def _pkexec_write(path: str, value: str) -> tuple[bool, str]:
    """Root-only sysfs write via polkit prompt. Returns (ok, message)."""
    if not shutil.which("pkexec"):
        return False, "pkexec not available"
    try:
        r = subprocess.run(["pkexec", "sh", "-c", 'printf "%s" "$1" > "$2"', "_", value, path],
                           capture_output=True, text=True, timeout=45)
    except subprocess.TimeoutExpired:
        return False, "timed out waiting for the password prompt"
    if r.returncode == 0:
        return True, "applied"
    if r.returncode in (126, 127):
        return False, "authorization cancelled"
    return False, (r.stderr or r.stdout).strip()[:200] or f"failed (rc={r.returncode})"

def _privileged_control(action: str, value: str, fallback_path: str) -> tuple[bool, str]:
    """Use the narrowly-scoped root helper when installed; preserve legacy pkexec fallback."""
    if not os.path.exists(HW_HELPER):
        return _pkexec_write(fallback_path, value)
    try:
        r = subprocess.run(["pkexec", HW_HELPER, action, value], capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        return False, "hardware helper timed out"
    if r.returncode == 0:
        return True, (r.stdout.strip() or "applied")
    return False, (r.stderr or r.stdout).strip()[:200] or f"hardware helper failed (rc={r.returncode})"

def set_platform_profile(p: str) -> tuple[bool, str]:
    choices = platform_profile()["choices"]
    if p not in choices and p not in ("power-saver", "balanced", "performance"):
        return False, f"choices: {choices}"
    m = {"quiet": "power-saver", "power-saver": "power-saver", "balanced": "balanced", "performance": "performance"}
    target = m.get(p, p)
    # asusctl is optional. When present it sets the matching firmware thermal
    # profile, which is the supported way to influence fan behaviour here.
    if shutil.which("asusctl"):
        asus_profile = {"power-saver": "Quiet", "balanced": "Balanced", "performance": "Performance"}.get(target)
        if asus_profile:
            try:
                r = subprocess.run(["asusctl", "profile", "set", asus_profile], capture_output=True, text=True, timeout=8)
                if r.returncode:
                    return False, (r.stderr or r.stdout).strip() or "ASUS thermal profile failed"
            except (OSError, subprocess.SubprocessError) as e:
                return False, f"ASUS thermal profile failed: {e}"
            return True, "ASUS thermal profile applied"
    # Non-ASUS fallback. Do not use this as a prerequisite on ASUS machines:
    # the distro helper may be unavailable in the backend's virtualenv.
    try:
        ppd = subprocess.run(["powerprofilesctl", "set", target], capture_output=True, text=True, timeout=5)
        if ppd.returncode == 0:
            return True, "power profile applied"
        return False, (ppd.stderr or ppd.stdout).strip() or "power profile failed"
    except (OSError, subprocess.SubprocessError) as e:
        return False, f"power profile failed: {e}"

def set_keyboard_backlight(level: int) -> tuple[bool, str]:
    kb = keyboard_backlight()
    if not kb.get("present"):
        return False, "no keyboard backlight device"
    level = max(0, min(kb["max"], int(level)))
    subprocess.run(["brightnessctl", "-q", "-d", kb["device"], "s", str(level)], timeout=5)
    return True, f"level {level}"

def set_charge_limit(pct: int) -> tuple[bool, str]:
    b = glob.glob("/sys/class/power_supply/BAT*")
    if not b:
        return False, "no battery"
    pct = max(40, min(100, int(pct)))
    return _privileged_control("charge-limit", str(pct), f"{b[0]}/charge_control_end_threshold")

def set_gpu_mux(mode: str) -> tuple[bool, str]:
    """Switch the ASUS GPU MUX; it takes effect at the next restart.
    hybrid — the iGPU draws the desktop, the NVIDIA GPU sleeps until something needs it
    dgpu   — the NVIDIA GPU drives the screens: most GPU performance, most power"""
    v = {"hybrid": "1", "dgpu": "0"}.get(mode)
    if v is None:
        return False, "mode must be hybrid or dgpu"
    if not mux()["supported"]:
        return False, "this laptop has no switchable GPU MUX"
    ok, msg = _privileged_control("gpu-mux", v, SYS_MUX if os.path.exists(SYS_MUX) else SYS_MUX_OLD)
    if ok:
        try:
            pathlib.Path(MUX_REQUEST).write_text(v)
        except OSError:
            pass
    return ok, ("restart to finish switching the GPU mode" if ok else msg)

def set_fan_mode(mode: str) -> tuple[bool, str]:
    a = _hwmon("asus")
    if not a:
        return False, "no asus fan interface"
    v = {"auto": "2", "full": "0"}.get(mode)
    if v is None:
        return False, "mode must be auto or full (curves need asusctl)"
    return _privileged_control("fan", v, f"{a}/pwm1_enable")
