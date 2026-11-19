import Foundation
import CoreBluetooth
import Combine
import UIKit
import AVFAudio

@MainActor
final class HeadphoneStore: ObservableObject {
    @Published private(set) var ledger = HeadphoneLedger()
    @Published private(set) var connectedHeadphones: [ConnectedHeadphone] = []
    @Published private(set) var storageError: String?
    private var storageURL: URL?
    private var canSave = true
    private var routeToken: NSObjectProtocol?
    private lazy var reader = ConnectedHeadphoneReader { [weak self] devices in
        guard let self = self, self.connectedHeadphones != devices else { return }
        self.connectedHeadphones = devices
    }

    init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Headphones", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            let url = directory.appendingPathComponent("devices-v1.json")
            storageURL = url
            if FileManager.default.fileExists(atPath: url.path) {
                ledger = try JSONDecoder().decode(HeadphoneLedger.self, from: Data(contentsOf: url))
            }
        } catch {
            // Preserve an unreadable legacy file and all existing color choices.
            canSave = false
            storageError = "设备偏好暂时无法读取或保存。\(error.localizedDescription)"
        }
        routeToken = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard UIApplication.shared.applicationState == .active else { return }
                self?.refresh()
            }
        }
    }

    deinit { if let token = routeToken { NotificationCenter.default.removeObserver(token) } }

    func start() { reader.start(requestPermission: false) }
    func stop() { reader.stop() }
    func refresh() { reader.start(requestPermission: false) }
    func detectConnectedHeadphones() { reader.start(requestPermission: true) }
    var bluetoothAccessDenied: Bool { CBManager.authorization == .denied || CBManager.authorization == .restricted }

    func setHistoryColor(_ color: HeadphoneColor, for key: String) {
        ledger.setHistoryColor(color, for: key)
        save()
    }

    private func save() {
        guard canSave, let url = storageURL else { return }
        do {
            let data = try JSONEncoder().encode(ledger)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            storageError = nil
        } catch {
            storageError = "设备偏好尚未保存。\(error.localizedDescription)"
        }
    }
}

/// Uses only system-connected peripherals exposing Device Information (180A).
/// No nearby scan, pairing list, private API, background mode or GATT writes.
@MainActor
private final class ConnectedHeadphoneReader: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private let update: ([ConnectedHeadphone]) -> Void
    private var central: CBCentralManager?
    private var active = false
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var readingInformation: [UUID: BluetoothDeviceInformation] = [:]
    private var state = ConnectedHeadphoneState()
    private var pending: [UUID: Set<CBUUID>] = [:]
    private var releases: Set<UUID> = []
    private var deadline: Timer?
    private var refreshTimer: Timer?
    private var confirmationTimer: Timer?
    #if DEBUG
    private var probeEvents: [[String: Any]] = []
    #endif
    private let serviceID = CBUUID(string: "180A")
    private let modelID = CBUUID(string: "2A24")
    private let manufacturerID = CBUUID(string: "2A29")
    private let pnpID = CBUUID(string: "2A50")

    init(update: @escaping ([ConnectedHeadphone]) -> Void) {
        self.update = update
        super.init()
    }

    func start(requestPermission: Bool) {
        guard requestPermission || CBManager.authorization != .notDetermined else { return }
        active = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else if central?.state == .poweredOn {
            queryConnected()
        } else if central?.state == .poweredOff || central?.state == .unauthorized || central?.state == .unsupported {
            clearResults()
        }
        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.active, self.central?.state == .poweredOn else { return }
                    self.queryConnected()
                }
            }
        }
    }

    func stop() {
        active = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        cancelReads()
        // Scene transitions must not erase an identity already read successfully.
        // On returning to the foreground we revalidate the system connection.
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard active else { return }
        if central.state == .poweredOn { queryConnected() }
        else if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported { clearResults() }
    }

    private func queryConnected() {
        guard active, let central = central, central.state == .poweredOn else { return }
        // Finish any previous app-local reads before querying system connections.
        // Completed reads are already released, so they cannot keep an otherwise
        // disconnected headset in this result just because our app holds a link.
        guard peripherals.isEmpty else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceID])
        state.reconcile(Dictionary(uniqueKeysWithValues: connected.map { ($0.identifier, $0.name ?? "") }), at: Date())
        // Manufacturer/model/PnP identity does not change every 15 seconds.
        // Reuse completed reads while the same system connection remains present.
        for peripheral in connected where state.information[peripheral.identifier] == nil {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
        publish()
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        if state.needsConfirmation {
            confirmationTimer = Timer.scheduledTimer(withTimeInterval: 2.1, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.queryConnected() }
            }
        }
        deadline?.invalidate()
        if !peripherals.isEmpty {
            deadline = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    for id in Array(self.peripherals.keys) { self.release(id) }
                    self.publish()
                    if self.state.needsConfirmation { self.queryConnected() }
                }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active, peripherals[peripheral.identifier] != nil else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverServices([serviceID])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard active, peripherals[peripheral.identifier] != nil else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            fail(peripheral.identifier)
            return
        }
        peripheral.discoverCharacteristics([modelID, manufacturerID, pnpID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard active, peripherals[peripheral.identifier] != nil else { return }
        let readable = (service.characteristics ?? []).filter {
            [modelID, manufacturerID, pnpID].contains($0.uuid) && $0.properties.contains(.read)
        }
        guard error == nil, !readable.isEmpty else { fail(peripheral.identifier); return }
        readingInformation[peripheral.identifier] = BluetoothDeviceInformation()
        pending[peripheral.identifier] = Set(readable.map { $0.uuid })
        for characteristic in readable { peripheral.readValue(for: characteristic) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier
        guard active, peripherals[id] != nil, pending[id]?.contains(characteristic.uuid) == true else { return }
        if error == nil, let data = characteristic.value {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            switch characteristic.uuid {
            case modelID: readingInformation[id]?.modelNumber = text
            case manufacturerID: readingInformation[id]?.manufacturer = text
            case pnpID: readingInformation[id]?.pnpID = data
            default: break
            }
        }
        pending[id]?.remove(characteristic.uuid)
        if pending[id]?.isEmpty == true {
            if let info = readingInformation[id] { state.finishRead(info, for: id) }
            publish()
            release(id)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fail(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if releases.remove(peripheral.identifier) != nil { return }
        guard peripherals[peripheral.identifier] != nil else { return }
        fail(peripheral.identifier)
    }

    private func fail(_ id: UUID) {
        release(id)
        publish()
    }

    private func release(_ id: UUID) {
        guard let peripheral = peripherals.removeValue(forKey: id) else { return }
        pending.removeValue(forKey: id)
        readingInformation.removeValue(forKey: id)
        releases.insert(id)
        central?.cancelPeripheralConnection(peripheral)
        if peripherals.isEmpty { deadline?.invalidate(); deadline = nil }
    }

    private func cancelReads() {
        let old = Array(peripherals.values)
        peripherals = [:]
        pending = [:]
        readingInformation = [:]
        deadline?.invalidate()
        deadline = nil
        for peripheral in old {
            releases.insert(peripheral.identifier)
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    private func clearResults() {
        cancelReads()
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        state.clear()
        publish()
    }

    private func publish() {
        guard active else { return }
        let devices = state.devices
        update(devices)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--probe-bluetooth") {
            let rows: [[String: Any]] = devices.map {
                ["product": $0.product.title, "model": $0.information.modelNumber ?? "",
                 "manufacturer": $0.information.manufacturer ?? "",
                 "productID": $0.information.appleProductID.map { String(format: "0x%04x", $0) } ?? ""]
            }
            probeEvents.append(["time": Date().timeIntervalSince1970, "count": devices.count,
                                "pendingReads": peripherals.count])
            probeEvents = Array(probeEvents.suffix(120))
            let trace = FileManager.default.temporaryDirectory.appendingPathComponent("headphone-connection-trace.json")
            if let data = try? JSONSerialization.data(withJSONObject: probeEvents, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: trace, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("connected-headphones.json")
            if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        #endif
    }
}
