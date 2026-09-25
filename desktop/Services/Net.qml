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

    function setWifi(on) { Networking.wifiEnabled = on }
    function scan() { if (wifiDevice) wifiDevice.scannerEnabled = true }
    function stopScan() { if (wifiDevice) wifiDevice.scannerEnabled = false }

    // ── bluetooth ──────────────────────────────────────────────────────
    readonly property var  adapter: Bluetooth.defaultAdapter
    readonly property bool btAvailable: !!adapter
    readonly property bool btEnabled: adapter ? adapter.enabled : false
    readonly property var  btDevices: adapter ? adapter.devices.values : []
    readonly property var  btConnected: btDevices.filter(d => d.connected)
    readonly property string btLabel: !btAvailable ? "No adapter" : !btEnabled ? "Off"
                                    : btConnected.length ? btConnected.map(d => d.name || d.deviceName).join(", ") : "On"

    function setBt(on) { if (adapter) adapter.enabled = on }
    function setDiscovering(on) { if (adapter) adapter.discovering = on }
}
