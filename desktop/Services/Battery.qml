pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Battery history — rolling 60-minute window sampled every 30 s.  Consumers
// pull `series` (0..120 samples, 0..1 percentage) plus estimated time-to-
// empty / time-to-full derived from the recent slope.
Singleton {
    id: root

    readonly property var  dev: UPower.displayDevice
    readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage / 100 : dev.percentage) : 1
    readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging
                                              || dev.state === UPowerDeviceState.FullyCharged)
    readonly property real rateW: dev ? Math.abs(dev.energyRate || 0) : 0   // W

    // rolling series
    property var series: []       // list of {t, p}
    readonly property int maxSamples: 120
    readonly property real windowSecs: 60 * 60

    Timer {
        interval: 30_000
        running: !!root.dev
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now() / 1000
            const s = root.series.slice()
            s.push({ t: now, p: root.pct })
            while (s.length > root.maxSamples || (s.length > 2 && now - s[0].t > root.windowSecs)) s.shift()
            root.series = s
        }
    }

    // slope over the last ~10 min → ETA
    readonly property real slopePctPerHour: {
        const n = series.length
        if (n < 3) return 0
        const cutoff = series[n - 1].t - 600
        const win = series.filter(x => x.t >= cutoff)
        if (win.length < 2) return 0
        const a = win[0], b = win[win.length - 1]
        const dt = (b.t - a.t) / 3600
        return dt > 0 ? (b.p - a.p) / dt * 100 : 0    // %/hour
    }
    readonly property string eta: {
        if (!dev) return ""
        const slope = slopePctPerHour
        if (charging) {
            if (slope <= 0) return ""
            const hrs = (1 - pct) * 100 / slope
            return hrs < 1/6 ? "moments" : _fmtHrs(hrs) + " to full"
        }
        if (slope >= 0) return ""
        const hrs = pct * 100 / -slope
        return hrs < 1/6 ? "moments" : _fmtHrs(hrs) + " left"
    }

    function _fmtHrs(h) {
        const m = Math.round(h * 60)
        if (m < 60) return m + " min"
        return Math.floor(m / 60) + "h " + (m % 60) + "m"
    }
}
