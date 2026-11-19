import Foundation

enum HeadphoneColor: String, CaseIterable, Identifiable {
    case starlight, midnight, blue, purple, orange
    var id: String { rawValue }
    var title: String {
        switch self {
        case .starlight: return "星光色"
        case .midnight: return "午夜色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .orange: return "橙色"
        }
    }
    var assetName: String {
        switch self {
        case .starlight: return "AirPodsMaxStarlight"
        case .midnight: return "AirPodsMax"
        case .blue: return "AirPodsMaxBlue"
        case .purple: return "AirPodsMaxPurple"
        case .orange: return "AirPodsMaxOrange"
        }
    }
}

// Display models are independent of route names and device identity. A renamed
// audio output is never used as proof of a product model or historical owner.
enum HeadphoneProduct: String, CaseIterable, Identifiable {
    case airPodsGeneric, airPodsMaxGeneric
    case airPods1, airPods2, airPods3, airPods4, airPods4ANC, airPods5, airPods5Wireless
    case airPodsPro, airPodsPro2, airPodsPro2USBC, airPodsPro3
    case airPodsMax, airPodsMaxUSBC, airPodsMax2
    var id: String { rawValue }
    var title: String {
        switch self {
        case .airPodsGeneric: return "AirPods"
        case .airPodsMaxGeneric: return "AirPods Max"
        case .airPods1: return "AirPods（第 1 代）"
        case .airPods2: return "AirPods（第 2 代）"
        case .airPods3: return "AirPods（第 3 代）"
        case .airPods4: return "AirPods 4"
        case .airPods4ANC: return "AirPods 4（主动降噪）"
        case .airPods5: return "AirPods 5"
        case .airPods5Wireless: return "AirPods 5（无线充电盒）"
        case .airPodsPro: return "AirPods Pro"
        case .airPodsPro2: return "AirPods Pro 2（闪电接口）"
        case .airPodsPro2USBC: return "AirPods Pro 2（USB-C）"
        case .airPodsPro3: return "AirPods Pro 3"
        case .airPodsMax: return "AirPods Max（闪电接口）"
        case .airPodsMaxUSBC: return "AirPods Max（USB-C）"
        case .airPodsMax2: return "AirPods Max 2"
        }
    }
    var supportsColor: Bool { [.airPodsMaxGeneric, .airPodsMax, .airPodsMaxUSBC, .airPodsMax2].contains(self) }
    func assetName(color: HeadphoneColor = .starlight) -> String {
        switch self {
        case .airPodsGeneric: return "AirPodsClassic"
        case .airPods1: return "AirPods1"
        case .airPods2: return "AirPods2"
        case .airPods3: return "AirPods3"
        case .airPods4, .airPods4ANC: return "AirPods4"
        case .airPods5, .airPods5Wireless: return "AirPods5"
        case .airPodsPro: return "AirPodsPro"
        case .airPodsPro2, .airPodsPro2USBC: return "AirPodsPro2"
        case .airPodsPro3: return "AirPodsPro3"
        case .airPodsMaxGeneric, .airPodsMax, .airPodsMaxUSBC, .airPodsMax2: return color.assetName
        }
    }
    var symbol: String {
        if supportsColor { return "airpodsmax" }
        return rawValue.contains("Pro") ? "airpodspro" : "airpods"
    }
    static func resolve(_ raw: String?) -> HeadphoneProduct? {
        guard let raw = raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let identifiers: [String: HeadphoneProduct] = [
            "0x2002": .airPods1, "a1523": .airPods1, "a1722": .airPods1,
            "0x200f": .airPods2, "a2032": .airPods2, "a2031": .airPods2,
            "0x2013": .airPods3, "a2565": .airPods3, "a2564": .airPods3,
            "0x2019": .airPods4, "a3053": .airPods4, "a3050": .airPods4, "a3054": .airPods4,
            "0x201b": .airPods4ANC, "a3056": .airPods4ANC, "a3055": .airPods4ANC, "a3057": .airPods4ANC,
            "0x2036": .airPods5, "a3531": .airPods5, "a3532": .airPods5, "a3533": .airPods5,
            "0x2030": .airPods5Wireless, "a3439": .airPods5Wireless, "a3440": .airPods5Wireless, "a3441": .airPods5Wireless,
            "0x200e": .airPodsPro, "a2084": .airPodsPro, "a2083": .airPodsPro,
            "0x2014": .airPodsPro2, "a2931": .airPodsPro2, "a2699": .airPodsPro2, "a2698": .airPodsPro2,
            "0x2024": .airPodsPro2USBC, "a3047": .airPodsPro2USBC, "a3048": .airPodsPro2USBC, "a3049": .airPodsPro2USBC,
            "0x2027": .airPodsPro3, "a3063": .airPodsPro3, "a3064": .airPodsPro3, "a3065": .airPodsPro3,
            "0x200a": .airPodsMax, "a2096": .airPodsMax,
            "0x201f": .airPodsMaxUSBC, "a3184": .airPodsMaxUSBC,
            "0x202d": .airPodsMax2, "a3454": .airPodsMax2
        ]
        if let product = identifiers[value] { return product }
        let name = value.filter { $0.isLetter || $0.isNumber }
        let names: [String: HeadphoneProduct] = [
            "airpods": .airPodsGeneric, "airpods1": .airPods1, "airpods2": .airPods2,
            "airpods3": .airPods3, "airpods4": .airPods4, "airpods4anc": .airPods4ANC,
            "airpods5": .airPods5, "airpodspro": .airPodsPro, "airpodspro2": .airPodsPro2,
            "airpodspro2usbc": .airPodsPro2USBC, "airpodspro3": .airPodsPro3,
            "airpodsmax": .airPodsMaxGeneric, "airpodsmaxusbc": .airPodsMaxUSBC, "airpodsmax2": .airPodsMax2
        ]
        return names[name]
    }

    static func suggestedByName(_ name: String) -> HeadphoneProduct? {
        if let exact = resolve(name) { return exact }
        let text = name.lowercased().replacingOccurrences(of: "’", with: "'")
        // Route names may contain an owner's prefix. This only suggests artwork;
        // it never establishes identity, history attribution, or a generation.
        if text.contains("airpods max 2") { return .airPodsMax2 }
        if text.contains("airpods max") { return .airPodsMaxGeneric }
        if text.contains("airpods pro 3") { return .airPodsPro3 }
        if text.contains("airpods pro 2") { return .airPodsPro2 }
        if text.contains("airpods pro") { return .airPodsPro }
        if text.contains("airpods 5") { return .airPods5 }
        if text.contains("airpods 4") { return .airPods4 }
        if text.contains("airpods 3") { return .airPods3 }
        if text.contains("airpods 2") { return .airPods2 }
        if text.contains("airpods") { return .airPodsGeneric }
        return nil
    }
}

enum ListeningPeriod: String, CaseIterable, Identifiable {
    case day = "日", week = "周", month = "月", year = "年", all = "总共"
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year, .all: return .year
        }
    }

    var bucketComponent: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        case .year, .all: return .month
        }
    }

    func interval(offset: Int, now: Date = Date(), earliest: Date? = nil) -> DateInterval {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        if self == .all {
            let start = earliest.map { calendar.dateInterval(of: .month, for: $0)!.start } ?? Date(timeIntervalSince1970: 0)
            return DateInterval(start: min(start, now), end: now.addingTimeInterval(1))
        }
        let date = calendar.date(byAdding: component, value: offset, to: now) ?? now
        return calendar.dateInterval(of: component, for: date)!
    }
}

struct ListeningPoint: Identifiable {
    let date: Date
    let level: Double?
    let duration: TimeInterval?
    var id: Date { date }
}

struct ListeningRecord: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let level: Double
    let source: String
    var device: ListeningDeviceInfo? = nil
    var sourceID: String? = nil
}

struct ListeningDeviceInfo: Hashable {
    let name: String?
    let manufacturer: String?
    let model: String?
    let localIdentifier: String?
    var product: HeadphoneProduct? { HeadphoneProduct.resolve(model) }
    var recordKey: String {
        if let id = localIdentifier, !id.isEmpty { return "device:" + id }
        // Without a device identifier this is a model/source grouping, never an
        // assertion that two headphones of the same model are one physical unit.
        let fields = [manufacturer, model, name].map { $0 ?? "" }
        return "fields:" + fields.map { "\($0.utf8.count):\($0)" }.joined()
    }

    var description: String {
        [name, product?.title ?? model].compactMap { $0 }.filter { !$0.isEmpty }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }.joined(separator: " · ")
    }

    // A collector (for example iPhone or Apple Watch) is not the headphone.
    // Only an explicit headphone model can participate in the headphone ranking.
    var isHeadphone: Bool {
        if product != nil { return true }
        let value = (model ?? "").lowercased()
        return ["airpods", "earpods", "headphone", "powerbeats", "beats fit", "beats studio", "beats solo", "beats flex"].contains { value.contains($0) }
    }
    var headphoneKey: String? {
        guard isHeadphone else { return nil }
        if let id = localIdentifier, !id.isEmpty { return "device:\(id)" }
        return "model:\(manufacturer ?? ""):\(model ?? "")"
    }
    var symbol: String {
        if let product = product { return product.symbol }
        let value = (model ?? "").lowercased()
        if value.contains("airpods") {
            if value.contains("max") { return "airpodsmax" }
            if value.contains("pro") { return "airpodspro" }
            return "airpods"
        }
        if value.contains("earpods") { return "earpods" }
        return "headphones"
    }
}

struct ListeningSession: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let duration: TimeInterval
    let level: Double
    let source: String
    let device: ListeningDeviceInfo?
    let sampleCount: Int

    private struct Key: Hashable {
        let source: String
        let device: ListeningDeviceInfo?
        // A local identifier survives a rename. Otherwise require all available
        // device fields to agree instead of guessing from a model or route name.
        let deviceID: String?
        static func == (lhs: Key, rhs: Key) -> Bool {
            guard lhs.source == rhs.source else { return false }
            if lhs.deviceID != nil || rhs.deviceID != nil { return lhs.deviceID == rhs.deviceID }
            return lhs.device == rhs.device
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(source)
            if let id = deviceID { hasher.combine(id) } else { hasher.combine(device) }
        }
    }

    static func grouped(_ records: [ListeningRecord], within interval: DateInterval? = nil, now: Date = Date()) -> [ListeningSession] {
        var seen = Set<UUID>()
        let valid = records.compactMap { record -> ListeningRecord? in
            guard seen.insert(record.id).inserted, record.level.isFinite else { return nil }
            let start = max(record.start, interval?.start ?? record.start)
            let end = min(record.end, min(interval?.end ?? now, now))
            guard end > start else { return nil }
            return ListeningRecord(id: record.id, start: start, end: end, level: record.level, source: record.source, device: record.device, sourceID: record.sourceID)
        }
        let byDevice = Dictionary(grouping: valid) { record in
            Key(source: record.sourceID ?? record.source, device: record.device,
                deviceID: record.device?.localIdentifier.flatMap { $0.isEmpty ? nil : $0 })
        }
        var sessions: [ListeningSession] = []
        for samples in byDevice.values {
            let ordered = samples.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
            var run: [ListeningRecord] = []
            var end: Date?
            for sample in ordered {
                if let previousEnd = end, sample.start > previousEnd {
                    sessions.append(make(run))
                    run = []
                    end = nil
                }
                run.append(sample)
                end = max(end ?? sample.end, sample.end)
            }
            if !run.isEmpty { sessions.append(make(run)) }
        }
        return sessions.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start > $1.start }
    }

    private static func make(_ samples: [ListeningRecord]) -> ListeningSession {
        struct Edge { let date: Date; let energy: Double; let count: Int }
        // Integrate logarithmic sound energy over the union of covered time.
        // Overlapping samples share that time; they never add extra duration.
        let edges = samples.flatMap { sample -> [Edge] in
            let energy = pow(10, sample.level / 10)
            return [Edge(date: sample.start, energy: energy, count: 1), Edge(date: sample.end, energy: -energy, count: -1)]
        }.sorted { $0.date < $1.date }
        var count = 0
        var energy = 0.0
        var integratedEnergy = 0.0
        var duration = 0.0
        var previous = edges[0].date
        for edge in edges {
            let delta = edge.date.timeIntervalSince(previous)
            if count > 0, delta > 0 {
                integratedEnergy += max(0, energy) / Double(count) * delta
                duration += delta
            }
            count += edge.count
            energy += edge.energy
            if count == 0 { energy = 0 }
            previous = edge.date
        }
        let first = samples[0]
        return ListeningSession(id: first.id, start: first.start, end: samples.map(\.end).max()!, duration: duration,
                                level: duration > 0 && integratedEnergy > 0 ? 10 * log10(integratedEnergy / duration) : first.level,
                                source: first.source, device: samples.last?.device, sampleCount: samples.count)
    }
}

struct ListeningReport {
    let interval: DateInterval
    let duration: TimeInterval?
    let averageLevel: Double?
    let notificationCount: Int
    let points: [ListeningPoint]
    let records: [ListeningRecord]
    let updatedAt: Date
    var groupedSessions: [ListeningSession]? = nil
    var sessions: [ListeningSession] { groupedSessions ?? ListeningSession.grouped(records, within: interval, now: updatedAt) }

    var hasExposure: Bool { averageLevel != nil && points.contains { $0.level != nil } }
    var activeDays: Int {
        let calendar = Calendar.current
        var days = Set<Date>()
        for session in sessions {
            var day = calendar.startOfDay(for: session.start)
            while day < session.end {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days.count
    }
    var busiestPoint: ListeningPoint? {
        points.filter { ($0.duration ?? 0) > 0 }.max { ($0.duration ?? 0) < ($1.duration ?? 0) }
    }
    var loudestPoint: ListeningPoint? {
        points.filter { $0.level != nil }.max { ($0.level ?? 0) < ($1.level ?? 0) }
    }

    static func demo(period: ListeningPeriod, offset: Int, now: Date = Date()) -> ListeningReport {
        let demoStart = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        let interval = period.interval(offset: offset, now: now, earliest: demoStart)
        let calendar = Calendar.current
        let hours = [8, 9, 11, 13, 15, 18, 20, 21]
        let minutes = [14.0, 18, 24, 10, 16, 28, 22, 6]
        let levels = [62.0, 69, 73, 66, 71, 78, 72, 63]
        var records: [ListeningRecord] = []
        var day = interval.start
        while day < interval.end && day < now {
            let seed = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
            for (i, hour) in hours.enumerated() {
                guard let start = calendar.date(bySettingHour: hour, minute: 8 + i * 3, second: 0, of: day), start < now else { continue }
                let duration = (minutes[i] + Double(seed % 5 - 2)) * 60
                let end = min(start.addingTimeInterval(duration), now)
                guard end > start else { continue }
                let level = levels[i] + Double(seed % 7 - 3) + (seed % 4 == 0 && i == 5 ? 8 : 0)
                records.append(ListeningRecord(id: UUID(), start: start, end: end, level: level, source: "示例耳机"))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        var points: [ListeningPoint] = []
        var cursor = interval.start
        let component = period.bucketComponent
        while cursor < interval.end {
            let end = calendar.date(byAdding: component, value: 1, to: cursor)!
            let bucket = records.filter { $0.start >= cursor && $0.start < end }
            let duration = bucket.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            points.append(ListeningPoint(date: cursor, level: equivalentLevel(bucket), duration: duration > 0 ? duration : nil))
            cursor = end
        }
        let duration = records.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return ListeningReport(interval: interval, duration: duration > 0 ? duration : nil, averageLevel: equivalentLevel(records), notificationCount: 0, points: points, records: records.sorted { $0.start > $1.start }, updatedAt: now)
    }

    // Sound energy is logarithmic. This is used only to construct consistent demo data.
    // Real reports use HealthKit's equivalent-continuous-level statistics.
    private static func equivalentLevel(_ records: [ListeningRecord]) -> Double? {
        let duration = records.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard duration > 0 else { return nil }
        let energy = records.reduce(0) { $0 + pow(10, $1.level / 10) * $1.end.timeIntervalSince($1.start) }
        return 10 * log10(energy / duration)
    }
}

enum ListeningFormat {
    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds = seconds, seconds > 0 else { return "—" }
        let minutes = Int(seconds / 60)
        if minutes == 0 { return "不足 1 分钟" }
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
    }

    static func level(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "—"
    }

    static func dateRange(_ interval: DateInterval, period: ListeningPeriod) -> String {
        let start = interval.start
        let end = interval.end.addingTimeInterval(-1)
        switch period {
        case .day: return start.formatted(.dateTime.year().month().day().weekday(.wide))
        case .week: return start.formatted(.dateTime.month().day()) + " – " + end.formatted(.dateTime.month().day())
        case .month: return start.formatted(.dateTime.year().month(.wide))
        case .year: return start.formatted(.dateTime.year())
        case .all:
            return "全部可读历史 · " + start.formatted(.dateTime.year().month()) + " – " + end.formatted(.dateTime.year().month())
        }
    }
}
