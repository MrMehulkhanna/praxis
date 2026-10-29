pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth

// NetworkManager + BlueZ, via Quickshell's native D-Bus bindings. Event-driven.
Singleton {
    id: root

    // ── network ────────────────────────────────────────────────────────
    readonly property var wifiDevice: {
        const ds = Networking.devices.values
        for (const d of ds) if (d.type === DeviceType.Wifi) return d
        return null
    }
    readonly property var wiredDevice: {
        const ds = Networking.devices.values
        for (const d of ds) if (d.type === DeviceType.Wired && d.connected) return d
        return null
    }
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var  wifiNetworks: wifiDevice ? wifiDevice.networks.values : []
    readonly property var  activeWifi: {
        for (const n of wifiNetworks) if (n.connected) return n
        return null
    }
    readonly property bool   wifiConnected: !!activeWifi
    readonly property string ssid: activeWifi ? activeWifi.name : ""
    readonly property real   strength: activeWifi ? activeWifi.signalStrength / 100 : 0
    readonly property bool   wired: !!wiredDevice
    readonly property bool   online: Networking.connectivity === NetworkConnectivity.Full
    readonly property string icon: wired ? "ethernet" : (!wifiEnabled || !wifiConnected) ? "wifi-off" : "wifi"
    readonly property string label: wired ? "Wired" : !wifiEnabled ? "Wi-Fi off" : wifiConnected ? ssid : "Not connected"

    property bool scanning: false
    property int wifiScanRemaining: 0
    readonly property bool wifiScanning: wifiScanRemaining > 0 || scanning

    Timer {
        id: wifiScanCountdown
        interval: 1000
        repeat: true
        running: root.wifiScanRemaining > 0
        onTriggered: {
            root.wifiScanRemaining--
            if (root.wifiScanRemaining % 6 === 0 && root.wifiScanRemaining > 0) {
                Quickshell.execDetached(["nmcli", "dev", "wifi", "rescan"])
            }
            if (root.wifiScanRemaining <= 0) {
                root.stopWifiScan()
            }
        }
    }

    function setWifi(on) {
        Networking.wifiEnabled = on
        if (on) startWifiScan(30)
        else stopWifiScan()
    }

    function scan() {
        startWifiScan(30)
    }

    function startWifiScan(seconds) {
        if (wifiDevice) {
            wifiDevice.scannerEnabled = true
        }
        root.scanning = true
        root.wifiScanRemaining = seconds || 30
        Quickshell.execDetached(["nmcli", "dev", "wifi", "rescan"])
    }

    function stopWifiScan() {
        root.wifiScanRemaining = 0
        root.scanning = false
        if (wifiDevice) wifiDevice.scannerEnabled = false
    }

    function connectWifi(ssid, password) {
        if (!ssid) return
        if (password) {
            Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid, "password", password])
        } else {
            Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid])
        }
        connectRefreshTimer.restart()
    }

    Timer {
        id: connectRefreshTimer
        interval: 3500
        onTriggered: root.scan()
    }

    // ── bluetooth ──────────────────────────────────────────────────────
    readonly property var  adapter: Bluetooth.defaultAdapter
    readonly property bool btAvailable: !!adapter
    readonly property bool btEnabled: adapter ? adapter.enabled : false
    readonly property var  btDevices: adapter ? adapter.devices.values : []
    readonly property var  btConnected: btDevices.filter(d => d.connected)
    readonly property string btLabel: !btAvailable ? "No adapter" : !btEnabled ? "Off"
                                    : btConnected.length ? btConnected.map(d => d.name || d.deviceName).join(", ") : "On"

    property int btScanRemaining: 0
    readonly property bool btScanning: btScanRemaining > 0 || (adapter ? adapter.discovering : false)

    Timer {
        id: btScanCountdown
        interval: 1000
        repeat: true
        running: root.btScanRemaining > 0
        onTriggered: {
            root.btScanRemaining--
            if (root.btScanRemaining <= 0) {
                root.stopBtScan()
            }
        }
    }

    function setBt(on) {
        if (adapter) {
            adapter.enabled = on
            if (on) startBtScan(30)
            else stopBtScan()
        }
    }

    function setDiscovering(on) {
        if (adapter) {
            adapter.discovering = on
            if (on && btScanRemaining <= 0) btScanRemaining = 30
            else if (!on) btScanRemaining = 0
        }
    }

    function startBtScan(seconds) {
        if (!adapter) return
        if (!adapter.enabled) adapter.enabled = true
        adapter.discovering = true
        btScanRemaining = seconds || 30
    }

    function stopBtScan() {
        btScanRemaining = 0
        if (adapter) adapter.discovering = false
    }
}
