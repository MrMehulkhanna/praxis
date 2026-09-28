pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / memory / GPU stats. One process every 3 s, only while something
// on screen is actually showing them (Sys.active refcount).
Singleton {
    id: root

    property int active: 0            // consumers increment while visible
    property real cpu: 0              // 0..100
    property real mem: 0              // 0..100
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real gpu: 0              // 0..100
    property real vramUsedGb: 0
    property real vramTotalGb: 0
    property int  gpuTempC: 0
    property int  cpuTempC: 0
    property real netDown: 0          // bytes/s
    property real netUp: 0
    property var  _prevNet: null
    property real diskUsedGb: 0
    property real diskTotalGb: 0
    property real diskUsedPct: 0

    property var _prev: null

    Timer {
        interval: 3000
        running: root.active > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!probe.running) probe.running = true
    }

    Process {
        id: probe
        command: ["bash", "-c",
            "head -1 /proc/stat; " +
            "grep -E '^(MemTotal|MemAvailable)' /proc/meminfo; " +
            "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 'GPU_NA'; " +
            // CPU package temperature: Intel x86_pkg_temp zone, else the
            // coretemp/k10temp/zenpower hwmon, else the hottest zone. (A plain
            // max over all zones mixes in Wi-Fi/ACPI/NVMe sensors.)
            "t=''; for z in /sys/class/thermal/thermal_zone*; do [ \"$(cat $z/type 2>/dev/null)\" = x86_pkg_temp ] && t=$(cat $z/temp) && break; done; " +
            "[ -z \"$t\" ] && for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name 2>/dev/null) in coretemp|k10temp|zenpower) t=$(cat $h/temp1_input 2>/dev/null); break;; esac; done; " +
            "[ -z \"$t\" ] && t=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1); echo \"${t:-0}\"; " +
            "awk 'NR>2 && $1!=\"lo:\" {rx+=$2; tx+=$10} END {print \"NET\", rx, tx}' /proc/net/dev; " +
            // total across all real ext4/btrfs/xfs mounts (skip tmpfs/overlay)
            "df -k --output=fstype,size,used --local 2>/dev/null | " +
            "awk '$1 ~ /^(ext4|btrfs|xfs|f2fs|zfs)$/ {sz+=$2; us+=$3} END {print \"DISK\", sz, us}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n")
                if (lines.length < 3) return
                // cpu
                const c = lines[0].trim().split(/\s+/).slice(1).map(Number)
                const idle = c[3] + c[4], total = c.reduce((a, b) => a + b, 0)
                if (root._prev) {
                    const dt = total - root._prev.total, di = idle - root._prev.idle
                    if (dt > 0) root.cpu = Math.max(0, Math.min(100, 100 * (1 - di / dt)))
                }
                root._prev = { total, idle }
                // mem (kB)
                let mt = 0, ma = 0
                for (const l of lines.slice(1, 3)) {
                    const v = parseInt(l.split(/\s+/)[1])
                    if (l.startsWith("MemTotal")) mt = v; else ma = v
                }
                if (mt > 0) {
                    root.memTotalGb = mt / 1048576
                    root.memUsedGb  = (mt - ma) / 1048576
                    root.mem = 100 * (mt - ma) / mt
                }
                // gpu
                const g = lines[3] || "GPU_NA"
                if (g !== "GPU_NA") {
                    const p = g.split(",").map(s => parseFloat(s))
                    root.gpu = p[0]; root.vramUsedGb = p[1] / 1024; root.vramTotalGb = p[2] / 1024; root.gpuTempC = p[3]
                }
                const t = parseInt(lines[4] || "0")
                if (t > 0) root.cpuTempC = Math.round(t / 1000)
                const net = lines.find(l => l.startsWith("NET "))
                if (net) {
                    const p = net.split(" "); const rx = parseInt(p[1]), tx = parseInt(p[2]), now = Date.now()
                    if (root._prevNet) { const dt = (now - root._prevNet.t) / 1000; if (dt > 0) { root.netDown = (rx - root._prevNet.rx) / dt; root.netUp = (tx - root._prevNet.tx) / dt } }
                    root._prevNet = { t: now, rx, tx }
                }
                const disk = lines.find(l => l.startsWith("DISK "))
                if (disk) {
                    const p = disk.split(" "); const sz = parseInt(p[1]), us = parseInt(p[2])
                    if (sz > 0) {
                        root.diskTotalGb = sz / 1048576  // kB → GiB
                        root.diskUsedGb  = us / 1048576
                        root.diskUsedPct = 100 * us / sz
                    }
                }
            }
        }
    }
}
