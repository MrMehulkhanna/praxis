pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Battery — thin view over UPower's display device plus a rolling 1-hour
// history for spark lines. ETA and power draw come straight from UPower
// (timeToEmpty / timeToFull / changeRate), which already smooths them.
Singleton {
    id: root

    readonly property var  dev: UPower.displayDevice
    readonly property bool present: !!dev && dev.isLaptopBattery && dev.isPresent
    readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage / 100 : dev.percentage) : 1
    readonly property bool charging: !!dev && (dev.state === UPowerDeviceState.Charging
                                              || dev.state === UPowerDeviceState.FullyCharged)
    readonly property real rateW: dev ? Math.abs(dev.changeRate || 0) : 0

    readonly property string eta: {
        if (!present) return ""
        if (dev.state === UPowerDeviceState.FullyCharged) return "fully charged"
        const secs = charging ? dev.timeToFull : dev.timeToEmpty
        if (!secs || secs <= 0) return ""
        return fmtSecs(secs) + (charging ? " to full" : " left")
    }

    function fmtSecs(s) {
        const m = Math.round(s / 60)
        if (m < 60) return m + " min"
        return Math.floor(m / 60) + "h " + (m % 60) + "m"
    }

    // rolling history: one sample every 30 s, trimmed to the last hour
    property var series: []
    Timer {
        interval: 30000
        running: root.present
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now() / 1000
            const s = root.series.filter(x => now - x.t <= 3600)
            s.push({ t: now, p: root.pct })
            root.series = s
        }
    }
}
