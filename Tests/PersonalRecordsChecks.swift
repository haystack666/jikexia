import Foundation

@main
enum PersonalRecordsChecks {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
        let now = date("2026-12-01T00:00:00Z")
        func sample(_ start: String, _ end: String, device: ListeningDeviceInfo? = nil) -> ListeningRecord {
            ListeningRecord(id: UUID(), start: date(start), end: date(end), level: 70, source: "test", device: device)
        }
        let phone = ListeningDeviceInfo(name: "AirPods renamed iPhone", manufacturer: "Apple", model: "iPhone18,1", localIdentifier: "phone")
        let pods = ListeningDeviceInfo(name: "AirPods", manufacturer: "Apple", model: "AirPods Pro", localIdentifier: "pods")
        precondition(HeadphoneProduct.resolve(" 0x202D ") == .airPodsMax2)
        precondition(HeadphoneProduct.resolve("A3047") == .airPodsPro2USBC)
        precondition(HeadphoneProduct.resolve("a1523") == .airPods1)
        precondition(HeadphoneProduct.resolve("A2032") == .airPods2)
        precondition(HeadphoneProduct.resolve("0xffff") == nil)
        precondition(HeadphoneProduct.resolve("iPhone18,1") == nil)
        precondition(HeadphoneProduct.resolve("AirPods Max") == .airPodsMaxGeneric, "Name alone must not imply a generation")
        precondition(ListeningDeviceInfo(name: nil, manufacturer: "Apple", model: "0x202d", localIdentifier: nil).isHeadphone)
        let rows = [
            sample("2026-10-31T23:00:00-04:00", "2026-11-01T02:00:00-05:00", device: pods), // 4h across DST and midnight
            sample("2026-10-31T23:30:00-04:00", "2026-11-01T01:30:00-04:00", device: pods), // duplicate overlap
            sample("2026-11-01T02:00:00-05:00", "2026-11-01T03:00:00-05:00", device: pods), // touching interval
            sample("2026-11-02T12:00:00-05:00", "2026-11-02T13:00:00-05:00", device: phone),
            sample("2026-11-04T12:00:00-05:00", "2026-11-04T12:30:00-05:00"),
            sample("2027-01-01T12:00:00-05:00", "2027-01-01T15:00:00-05:00"), // future ignored
            sample("2026-11-01T12:00:00-05:00", "2026-11-01T12:00:00-05:00") // zero ignored
        ]
        let result = PersonalRecords.calculate(rows, calendar: calendar, now: now)
        precondition(result.totalDuration == 6.5 * 3600, "Overlapping samples must be counted once")
        precondition(result.longestSession?.duration == 5 * 3600, "Touching intervals merge across midnight and DST")
        precondition(result.longestDay?.duration == 4 * 3600, "Cross-midnight time must be split correctly")
        precondition(result.longestDay?.date == date("2026-11-01T00:00:00-04:00"))
        precondition(result.longestStreak?.days == 3, "Streak uses calendar days across DST")
        precondition(result.longestStreak?.start == date("2026-10-31T00:00:00-04:00"))
        precondition(result.longestStreak?.end == date("2026-11-02T00:00:00-05:00"))
        precondition(result.bestMonth?.days == 3 && result.bestMonth?.duration == 5.5 * 3600)
        precondition(result.activeDays == 4)
        precondition(result.days.count == 4 && result.days.reduce(0) { $0 + $1.duration } == result.totalDuration,
                     "Calendar daily coverage must equal all-history coverage without duplicate overlap")
        precondition(result.days.first?.date == date("2026-10-31T00:00:00-04:00") && result.days.first?.duration == 3600,
                     "Calendar must split midnight in the current timezone")
        precondition(result.days.first { $0.date == date("2026-11-01T00:00:00-04:00") }?.duration == 4 * 3600,
                     "Calendar must retain the extra hour across the DST transition")
        precondition(!result.days.contains { $0.date == date("2026-11-03T00:00:00-05:00") },
                     "An unrecorded day must remain absent, never fabricated as usage")
        precondition(result.headphones.count == 1 && result.headphones.first?.duration == 5 * 3600, "Collector is not a headphone, names are not model evidence")
        precondition(result.unattributedDuration == 1.5 * 3600)
        precondition(result.recordedDevices.count == 2, "Health history devices must populate the inventory, including collectors")
        precondition(result.recordedDevices.first { $0.device.isHeadphone }?.duration == 5 * 3600)
        let podStats = result.recordedDevices.first { $0.device.isHeadphone }!.statistics
        precondition(podStats.days.count == 2 && podStats.days.reduce(0) { $0 + $1.duration } == 5 * 3600, "Device detail splits midnight and DST without counting overlap twice")
        precondition(podStats.sessions.count == 1 && podStats.averageSession == 5 * 3600, "Device detail uses merged listening sessions, not minute sample counts")
        precondition(abs(podStats.averageLevel! - 70) < 0.00001)
        precondition(podStats.duration(since: date("2026-11-01T00:00:00-04:00")) == 4 * 3600)
        let sameMinute = sample("2026-11-14T12:00:00Z", "2026-11-14T12:01:00Z", device: pods)
        let minuteStats = DeviceListeningStatistics.calculate([
            sameMinute, sameMinute,
            sample("2026-11-14T12:01:00Z", "2026-11-14T12:02:00Z", device: pods),
            sample("2026-11-14T12:02:30Z", "2026-11-14T12:03:30Z", device: pods)
        ], calendar: calendar, now: now)
        precondition(minuteStats.sessions.count == 2 && minuteStats.averageSession == 90)
        precondition(minuteStats.days.reduce(0) { $0 + $1.duration } == 180, "Do not fill gaps or double-count duplicate minute samples")
        var quiet = sample("2026-11-14T12:00:00Z", "2026-11-14T13:00:00Z", device: pods)
        quiet = ListeningRecord(id: quiet.id, start: quiet.start, end: quiet.end, level: 60, source: "one", device: pods)
        let loud = ListeningRecord(id: UUID(), start: quiet.start, end: quiet.end, level: 80, source: "two", device: pods)
        let mixed = DeviceListeningStatistics.calculate([quiet, loud], calendar: calendar, now: now)
        precondition(mixed.days.reduce(0) { $0 + $1.duration } == 3600, "Overlapping sources must not inflate chart totals")
        precondition(mixed.sessions.count == 2, "Keep different record sources as separate listening sessions")
        precondition(abs(mixed.averageLevel! - 10 * log10((pow(10, 6) + pow(10, 8)) / 2)) < 0.00001, "Sound level uses logarithmic energy, not arithmetic dB average")
        let emptyStats = DeviceListeningStatistics.calculate([], calendar: calendar, now: now)
        precondition(emptyStats.averageLevel == nil && emptyStats.averageSession == nil && emptyStats.sessions.isEmpty && emptyStats.days.isEmpty)
        let renamedPods = ListeningDeviceInfo(name:"狗叫屏蔽器",manufacturer:"Apple Inc.",model:"0x202d",localIdentifier:nil)
        let recognized = PersonalRecords.calculate([sample("2026-11-14T12:00:00Z","2026-11-14T13:00:00Z",device:renamedPods)],now:now)
        precondition(recognized.recordedDevices.first?.device.product == .airPodsMax2, "History model IDs must work independently of the user's route name")
        precondition(recognized.recordedDevices.first?.id == recognized.headphones.first?.id, "Inventory and favourite must share the same colour preference")
        let switchSession = PersonalRecords.calculate([
            sample("2026-11-14T12:00:00Z","2026-11-14T13:00:00Z",device:pods),
            sample("2026-11-14T13:00:00Z","2026-11-14T14:00:00Z",device:renamedPods)
        ],now:now)
        precondition(switchSession.longestSession?.duration == 3600, "A headphone switch starts a different session")
        let empty = PersonalRecords.calculate([], calendar: calendar, now: now)
        precondition(empty.longestDay == nil && empty.longestSession == nil && empty.longestStreak == nil && empty.bestMonth == nil && empty.range == nil)
        let gap = PersonalRecords.calculate([
            sample("2026-11-10T12:00:00Z", "2026-11-10T13:00:00Z"),
            sample("2026-11-10T13:00:01Z", "2026-11-10T14:00:01Z")
        ], calendar: calendar, now: now)
        precondition(gap.longestSession?.duration == 3600, "Even a one-second gap must not be filled")
        let clipped = PersonalRecords.calculate([sample("2026-11-30T23:00:00Z", "2026-12-01T01:00:00Z")], calendar: calendar, now: now)
        precondition(clipped.totalDuration == 3600, "Future ends must be clipped")

        let pnp = Data([0x01, 0x4c, 0x00, 0x24, 0x20, 0x01, 0x00])
        let live = BluetoothDeviceInformation(manufacturer: "Apple Inc.", modelNumber: "A3049", pnpID: pnp)
        precondition(live.appleProductID == 0x2024 && live.product == .airPodsPro2USBC, "Decode actual standard PnP little-endian product ID")
        precondition(BluetoothDeviceInformation(pnpID: pnp).product == .airPodsPro2USBC, "PnP alone identifies a known Apple headphone")
        precondition(BluetoothDeviceInformation(modelNumber: " A3049 ").product == .airPodsPro2USBC)
        precondition(BluetoothDeviceInformation(manufacturer: "Other", modelNumber: "A3049", pnpID: pnp).product == nil)
        precondition(BluetoothDeviceInformation(modelNumber: "Watch7,9").product == nil, "Other connected Apple devices must not appear as headphones")
        precondition(BluetoothDeviceInformation(modelNumber: "AirPods Pro 2").product == nil, "Do not guess generations from product names")
        precondition(BluetoothDeviceInformation(pnpID: Data([0x01, 0x4c, 0x00, 0x24])).product == nil, "Truncated PnP is rejected")
        precondition(BluetoothDeviceInformation(pnpID: Data([0x01, 0x01, 0x00, 0x24, 0x20, 0x01, 0x00])).product == nil, "Other vendors must not share Apple's mapping")
        precondition(BluetoothDeviceInformation(pnpID: Data([0x02, 0xac, 0x05, 0x24, 0x20, 0x01, 0x00])).product == .airPodsPro2USBC, "USB vendor namespace uses Apple's USB ID")
        precondition(BluetoothDeviceInformation(modelNumber: "A2032", pnpID: pnp).product == nil, "Conflicting hardware and product IDs are rejected")
        precondition(BluetoothDeviceInformation(pnpID: Data([0x01, 0x4c, 0x00, 0x18, 0x20, 0x01, 0x00])).product == nil, "Unknown accessory IDs must not turn into duplicate headphone cards")

        var ledger = HeadphoneLedger()
        let a = AudioOutput(id: "a", name: "Same name", kind: "蓝牙音频", isHeadphone: true)
        let b = AudioOutput(id: "b", name: "Same name", kind: "蓝牙音频", isHeadphone: true)
        let speaker = AudioOutput(id: "speaker", name: "iPhone", kind: "内置扬声器", isHeadphone: false)
        ledger.observe([a, speaker], previousIDs: nil, at: now)
        precondition(ledger.devices.first?.displayColor == .starlight)
        ledger.setDisplayProduct(.airPodsMax2, for: "a")
        ledger.setDisplayColor(.purple, for: "a")
        ledger.setHistoryColor(.blue, for: "model:test")
        precondition(ledger.devices.count == 1 && ledger.events.first?.kind == .observed)
        ledger.observe([a], previousIDs: ["a"], at: now.addingTimeInterval(1))
        precondition(ledger.events.count == 1, "Refreshing unchanged route must not create events")
        ledger.observe([b], previousIDs: ["a"], at: now.addingTimeInterval(2))
        precondition(ledger.devices.count == 2, "Same names must not merge different IDs")
        precondition(ledger.events.contains { $0.kind == .leftOutput && $0.deviceID == "a" })
        ledger.observe([a], previousIDs: nil, at: now.addingTimeInterval(3))
        precondition(ledger.events.last?.kind == .observed, "Returning from suspension must not invent a switch time")
        ledger.observe([AudioOutput(id: "a", name: "Renamed", kind: "蓝牙音频", isHeadphone: true)], previousIDs: ["a"], at: now.addingTimeInterval(4))
        precondition(ledger.devices.first { $0.id == "a" }?.name == "Renamed")
        precondition(ledger.devices.first { $0.id == "a" }?.displayProduct == .airPodsMax2)
        precondition(ledger.devices.first { $0.id == "a" }?.displayColor == .purple, "Refreshing a route must preserve the user's choice")
        let restored = try JSONDecoder().decode(HeadphoneLedger.self, from: JSONEncoder().encode(ledger))
        precondition(restored.devices.first { $0.id == "a" }?.displayColor == .purple)
        precondition(restored.historyColor(for: "model:test") == .blue)
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        legacyJSON.removeValue(forKey: "historyArtworkColors")
        legacyJSON["devices"] = (legacyJSON["devices"] as! [[String: Any]]).map { row in
            var row = row
            row.removeValue(forKey: "displayColorID")
            row.removeValue(forKey: "displayProductID")
            return row
        }
        let legacy = try JSONDecoder().decode(HeadphoneLedger.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        precondition(legacy.devices.count == ledger.devices.count && legacy.devices.allSatisfy { $0.displayColor == .starlight && $0.displayProduct == nil })
        precondition(restored.events.count == ledger.events.count && restored.devices.count == ledger.devices.count)
        ledger.remove("a")
        precondition(!ledger.devices.contains { $0.id == "a" } && !ledger.events.contains { $0.deviceID == "a" })
        for i in 0..<260 {
            ledger.observe([AudioOutput(id: "bounded-\(i)", name: "Output", kind: "蓝牙音频", isHeadphone: true)], previousIDs: nil, at: now.addingTimeInterval(Double(i)))
        }
        precondition(ledger.devices.count == 50 && ledger.events.count <= 200)
        print("PASS: DST, midnight splitting, overlap deduplication, strict sessions, calendar streaks, month totals, attribution, future exclusion, device identity, foreground gaps, persistence, deletion, limits")
    }
}
