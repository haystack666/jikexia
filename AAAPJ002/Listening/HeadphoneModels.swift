import Foundation

struct AudioOutput: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
    let isHeadphone: Bool
}

struct RememberedHeadphone: Identifiable, Codable {
    let id: String
    var name: String
    var kind: String
    let firstSeen: Date
    var lastSeen: Date
    var displayProductID: String? = nil
    var displayColorID: String? = nil

    var displayProduct: HeadphoneProduct? { displayProductID.flatMap(HeadphoneProduct.init(rawValue:)) }
    var displayColor: HeadphoneColor { displayColorID.flatMap(HeadphoneColor.init(rawValue:)) ?? .starlight }
    var artworkProduct: HeadphoneProduct? { displayProduct ?? HeadphoneProduct.suggestedByName(name) }
    var identificationSummary: String {
        if let product = displayProduct { return "手动选择 · " + product.title }
        if let product = artworkProduct { return "名称建议 · " + product.title }
        return "型号待识别"
    }
}

struct HeadphoneEvent: Identifiable, Codable {
    enum Kind: String, Codable {
        case observed, becameOutput, leftOutput
        var title: String {
            switch self {
            case .observed: return "观察到耳机输出"
            case .becameOutput: return "切换为音频输出"
            case .leftOutput: return "离开音频输出"
            }
        }
        var symbol: String {
            switch self {
            case .observed: return "eye"
            case .becameOutput: return "arrow.down.right"
            case .leftOutput: return "arrow.up.right"
            }
        }
    }
    let id: UUID
    let deviceID: String
    let name: String
    let date: Date
    let kind: Kind
}

struct HeadphoneLedger: Codable {
    var devices: [RememberedHeadphone] = []
    var events: [HeadphoneEvent] = []
    var historyArtworkColors: [String: String]? = nil

    func historyColor(for key: String) -> HeadphoneColor {
        historyArtworkColors?[key].flatMap(HeadphoneColor.init(rawValue:)) ?? .starlight
    }

    mutating func setHistoryColor(_ color: HeadphoneColor, for key: String) {
        if historyArtworkColors == nil { historyArtworkColors = [:] }
        historyArtworkColors?[key] = color.rawValue
    }

    // previousIDs is nil at each foreground boundary: do not fabricate changes
    // that may have occurred while the app could not observe the route.
    mutating func observe(_ outputs: [AudioOutput], previousIDs: Set<String>?, at date: Date) {
        let headphones = outputs.filter { $0.isHeadphone && !$0.id.isEmpty }
        let currentIDs = Set(headphones.map { $0.id })
        for output in headphones {
            if let index = devices.firstIndex(where: { $0.id == output.id }) {
                devices[index].name = output.name
                devices[index].kind = output.kind
                devices[index].lastSeen = date
            } else {
                devices.append(RememberedHeadphone(id: output.id, name: output.name, kind: output.kind, firstSeen: date, lastSeen: date))
            }
            if previousIDs == nil || !previousIDs!.contains(output.id) {
                events.append(HeadphoneEvent(id: UUID(), deviceID: output.id, name: output.name, date: date, kind: previousIDs == nil ? .observed : .becameOutput))
            }
        }
        if let previousIDs = previousIDs {
            for id in previousIDs.subtracting(currentIDs).sorted() {
                guard let device = devices.first(where: { $0.id == id }) else { continue }
                events.append(HeadphoneEvent(id: UUID(), deviceID: id, name: device.name, date: date, kind: .leftOutput))
            }
        }
        devices.sort { $0.lastSeen > $1.lastSeen }
        devices = Array(devices.prefix(50))
        let keptIDs = Set(devices.map { $0.id })
        events = Array(events.filter { keptIDs.contains($0.deviceID) }.suffix(200))
    }

    mutating func remove(_ id: String) {
        devices.removeAll { $0.id == id }
        events.removeAll { $0.deviceID == id }
    }

    mutating func setDisplayProduct(_ product: HeadphoneProduct?, for id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].displayProductID = product?.rawValue
    }

    mutating func setDisplayColor(_ color: HeadphoneColor, for id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].displayColorID = color.rawValue
    }

}

/// Identity from the standard Bluetooth Device Information Service, never a
/// product guess based on a user-editable peripheral or audio-route name.
struct BluetoothDeviceInformation: Equatable {
    var manufacturer: String?
    var modelNumber: String?
    var pnpID: Data?

    var appleProductID: UInt16? {
        guard let data = pnpID, data.count == 7 else { return nil }
        let bytes = Array(data)
        let vendor = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        guard (bytes[0] == 1 && vendor == 0x004c) || (bytes[0] == 2 && vendor == 0x05ac) else { return nil }
        return UInt16(bytes[3]) | UInt16(bytes[4]) << 8
    }

    var product: HeadphoneProduct? {
        if let manufacturer = manufacturer, !manufacturer.isEmpty,
           !["apple", "apple inc.", "apple inc"].contains(manufacturer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            return nil
        }
        let model = modelNumber?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        // Restrict model resolution to hardware identifiers. Names such as
        // "AirPods Pro 2" must not silently select a charging-port generation.
        let hardwareProduct: HeadphoneProduct?
        if model.hasPrefix("a"), model.count == 5, model.dropFirst().allSatisfy({ $0.isNumber }) {
            hardwareProduct = HeadphoneProduct.resolve(model)
        } else { hardwareProduct = nil }
        let pnpProduct = appleProductID.flatMap { HeadphoneProduct.resolve(String(format: "0x%04x", $0)) }
        if let hardwareProduct = hardwareProduct, let pnpProduct = pnpProduct, hardwareProduct != pnpProduct { return nil }
        return hardwareProduct ?? pnpProduct
    }
}

struct ConnectedHeadphone: Identifiable, Equatable {
    let id: String
    let name: String?
    let information: BluetoothDeviceInformation
    let product: HeadphoneProduct
}

/// Keeps verified identity independent of a GATT read in progress. A missing
/// enumeration is confirmed again after a short grace; radio-off clears at once.
struct ConnectedHeadphoneState {
    private(set) var information: [UUID: BluetoothDeviceInformation] = [:]
    private var names: [UUID: String] = [:]
    private var missingSince: [UUID: Date] = [:]
    private(set) var connectedIDs: Set<UUID> = []
    var needsConfirmation: Bool { !missingSince.isEmpty }

    mutating func reconcile(_ connected: [UUID: String], at date: Date) {
        let ids = Set(connected.keys)
        for id in connectedIDs.subtracting(ids) {
            if let missing = missingSince[id], date.timeIntervalSince(missing) >= 2 {
                information.removeValue(forKey: id)
                names.removeValue(forKey: id)
                connectedIDs.remove(id)
                missingSince.removeValue(forKey: id)
            } else if missingSince[id] == nil { missingSince[id] = date }
        }
        for (id, name) in connected {
            connectedIDs.insert(id)
            names[id] = name
            missingSince.removeValue(forKey: id)
        }
    }

    mutating func finishRead(_ value: BluetoothDeviceInformation, for id: UUID) {
        guard connectedIDs.contains(id), value.modelNumber != nil || value.pnpID != nil else { return }
        information[id] = value
    }

    mutating func clear() { self = ConnectedHeadphoneState() }

    var devices: [ConnectedHeadphone] {
        information.compactMap { id, info in
            guard connectedIDs.contains(id), let product = info.product else { return nil }
            return ConnectedHeadphone(id: "bluetooth:" + id.uuidString,
                                      name: names[id].flatMap { $0.isEmpty ? nil : $0 },
                                      information: info, product: product)
        }.sorted { $0.id < $1.id }
    }
}
