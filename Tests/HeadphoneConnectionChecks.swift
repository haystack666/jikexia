import Foundation

@main
struct HeadphoneConnectionChecks {
    static func main() {
        let id = UUID(), watch = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let airpods = BluetoothDeviceInformation(manufacturer: "Apple Inc.", modelNumber: "A3049", pnpID: Data([1, 0x4c, 0, 0x24, 0x20, 1, 0]))
        var state = ConnectedHeadphoneState()
        state.reconcile([id: "My headphones", watch: "Watch"], at: now)
        assert(state.devices.isEmpty)
        state.finishRead(airpods, for: id)
        assert(state.devices.count == 1 && state.devices[0].product == airpods.product)
        // Other devices completing, starting a read, or a failed read must not
        // remove a previously verified headset on the same system connection.
        state.finishRead(BluetoothDeviceInformation(modelNumber: "Watch7,9"), for: watch)
        state.finishRead(BluetoothDeviceInformation(), for: id)
        for seconds in [15.0, 30, 45] {
            state.reconcile([id: "Renamed", watch: "Watch"], at: now.addingTimeInterval(seconds))
            assert(state.devices.count == 1 && state.devices[0].name == "Renamed")
            assert(state.information[id] == airpods)
        }
        // A transient empty enumeration gets a bounded confirmation window.
        state.reconcile([:], at: now.addingTimeInterval(46))
        assert(state.devices.count == 1 && state.needsConfirmation)
        state.reconcile([id: "Renamed"], at: now.addingTimeInterval(47))
        assert(state.devices.count == 1)
        state.reconcile([:], at: now.addingTimeInterval(50))
        assert(state.devices.count == 1)
        state.reconcile([:], at: now.addingTimeInterval(52.1))
        assert(state.devices.isEmpty && state.information.isEmpty && !state.needsConfirmation)
        // Late callbacks cannot resurrect an absent device. A real reconnect
        // reads identity again, and adapter-off bypasses the grace immediately.
        state.finishRead(airpods, for: id)
        assert(state.devices.isEmpty)
        state.reconcile([id: "Again"], at: now.addingTimeInterval(60))
        assert(state.information[id] == nil)
        state.finishRead(airpods, for: id)
        assert(state.devices.count == 1)
        state.clear()
        assert(state.devices.isEmpty && state.connectedIDs.isEmpty)
        print("PASS: stable verified Bluetooth identity, parallel reads, renaming, transient absence, confirmed disconnect, reconnect, adapter off")
    }
}
