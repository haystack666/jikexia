import Foundation

struct PersonalDayRecord {
    let date: Date
    let duration: TimeInterval
}
struct PersonalStreakRecord {
    let start: Date
    let end: Date
    let days: Int
}
struct PersonalMonthRecord {
    let month: Date
    let days: Int
    let duration: TimeInterval
}
struct HeadphoneTotal: Identifiable {
    let id: String
    let device: ListeningDeviceInfo
    let duration: TimeInterval
}

struct RecordedListeningDevice: Identifiable {
    let id: String
    let device: ListeningDeviceInfo
    let firstSeen: Date
    let lastSeen: Date
    let duration: TimeInterval
    let sampleCount: Int
    let sources: [String]
    let statistics: DeviceListeningStatistics
}

struct DeviceListeningStatistics {
    let days: [PersonalDayRecord]
    let sessions: [ListeningSession]
    let averageLevel: Double?

    var averageSession: TimeInterval? {
        guard !sessions.isEmpty else { return nil }
        return sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)
    }
    var longestSession: ListeningSession? { sessions.max { $0.duration < $1.duration } }
    func duration(since start: Date) -> TimeInterval {
        days.filter { $0.date >= start }.reduce(0) { $0 + $1.duration }
    }

    static func calculate(_ records: [ListeningRecord], calendar: Calendar, now: Date) -> Self {
        let sessions = ListeningSession.grouped(records, now: now)
        // A single source/device key integrates overlapping samples once, even
        // when multiple collectors reported the same device at the same time.
        let coverage = ListeningSession.grouped(records.map {
            ListeningRecord(id: $0.id, start: $0.start, end: $0.end, level: $0.level, source: "coverage")
        }, now: now)
        var daily: [Date: TimeInterval] = [:]
        for session in coverage {
            var cursor = session.start
            while cursor < session.end {
                let day = calendar.startOfDay(for: cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let end = min(next, session.end)
                daily[day, default: 0] += end.timeIntervalSince(cursor)
                cursor = end
            }
        }
        let duration = coverage.reduce(0) { $0 + $1.duration }
        let energy = coverage.reduce(0) { $0 + pow(10, $1.level / 10) * $1.duration }
        return Self(days: daily.keys.sorted().map { PersonalDayRecord(date: $0, duration: daily[$0]!) },
                    sessions: sessions, averageLevel: duration > 0 && energy > 0 ? 10 * log10(energy / duration) : nil)
    }
}

struct PersonalRecords {
    let days: [PersonalDayRecord]
    let longestDay: PersonalDayRecord?
    let longestSession: DateInterval?
    let longestStreak: PersonalStreakRecord?
    let bestMonth: PersonalMonthRecord?
    let headphones: [HeadphoneTotal]
    let recordedDevices: [RecordedListeningDevice]
    let totalDuration: TimeInterval
    let unattributedDuration: TimeInterval
    let activeDays: Int
    let sampleCount: Int
    let range: DateInterval?
    let updatedAt: Date

    static func calculate(_ records: [ListeningRecord], calendar: Calendar = .current, now: Date = Date()) -> PersonalRecords {
        let valid = records.filter { $0.end > $0.start && $0.start < now }
        let intervals = merged(valid.map { DateInterval(start: $0.start, end: min($0.end, now)) })
        var dayDurations: [Date: TimeInterval] = [:]
        for interval in intervals {
            var cursor = interval.start
            while cursor < interval.end {
                let day = calendar.startOfDay(for: cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let end = min(next, interval.end)
                dayDurations[day, default: 0] += end.timeIntervalSince(cursor)
                cursor = end
            }
        }
        let dates = dayDurations.keys.sorted()
        let dailyRecords: [PersonalDayRecord] = dates.map { PersonalDayRecord(date: $0, duration: dayDurations[$0]!) }
        let longestDay = dailyRecords.max { (left: PersonalDayRecord, right: PersonalDayRecord) in
            if left.duration == right.duration { return left.date < right.date }
            return left.duration < right.duration
        }
        var streak: PersonalStreakRecord?
        var runStart: Date?
        var previous: Date?
        var count = 0
        for date in dates {
            if let previous = previous, calendar.date(byAdding: .day, value: 1, to: previous) == date { count += 1 }
            else { runStart = date; count = 1 }
            if count >= (streak?.days ?? 0) { streak = PersonalStreakRecord(start: runStart!, end: date, days: count) }
            previous = date
        }
        var months: [Date: (days: Int, duration: TimeInterval)] = [:]
        for day in dates {
            guard let month = calendar.dateInterval(of: .month, for: day)?.start else { continue }
            let current = months[month] ?? (0, 0)
            months[month] = (current.days + 1, current.duration + dayDurations[day]!)
        }
        let bestMonth = months.map { PersonalMonthRecord(month: $0.key, days: $0.value.days, duration: $0.value.duration) }.max {
            if $0.duration != $1.duration { return $0.duration < $1.duration }
            if $0.days != $1.days { return $0.days < $1.days }
            return $0.month < $1.month
        }
        let grouped = Dictionary(grouping: valid.filter { $0.device?.headphoneKey != nil }) { $0.device!.headphoneKey! }
        let totals: [HeadphoneTotal] = grouped.map { key, samples in
            let deviceIntervals: [DateInterval] = samples.map { DateInterval(start: $0.start, end: min($0.end, now)) }
            return HeadphoneTotal(id: key, device: samples[0].device!, duration: total(merged(deviceIntervals)))
        }
        let headphones = totals.sorted { (left: HeadphoneTotal, right: HeadphoneTotal) in
            if left.duration == right.duration { return left.id < right.id }
            return left.duration > right.duration
        }
        let identified = merged(valid.filter { $0.device?.headphoneKey != nil }.map { DateInterval(start: $0.start, end: min($0.end, now)) })
        let deviceGroups = Dictionary(grouping: valid.filter { $0.device != nil }) { record in
            record.device!.headphoneKey ?? record.device!.recordKey
        }
        var recordedDevices: [RecordedListeningDevice] = []
        for (key, samples) in deviceGroups {
            let latest = samples.max { $0.end < $1.end }!
            let sampleIntervals = samples.map { DateInterval(start: $0.start, end: min($0.end, now)) }
            let covered = total(merged(sampleIntervals))
            let sources = Array(Set(samples.map { $0.source })).sorted()
            recordedDevices.append(RecordedListeningDevice(id: key, device: latest.device!,
                                                           firstSeen: samples.map { $0.start }.min()!,
                                                           lastSeen: min(samples.map { $0.end }.max()!, now),
                                                           duration: covered, sampleCount: samples.count, sources: sources,
                                                           statistics: DeviceListeningStatistics.calculate(samples, calendar: calendar, now: now)))
        }
        recordedDevices.sort { $0.lastSeen == $1.lastSeen ? $0.id < $1.id : $0.lastSeen > $1.lastSeen }
        let longestSession = ListeningSession.grouped(valid, now: now).max {
            $0.duration == $1.duration ? $0.start < $1.start : $0.duration < $1.duration
        }.map { DateInterval(start: $0.start, end: $0.end) }
        return PersonalRecords(days: dailyRecords, longestDay: longestDay, longestSession: longestSession, longestStreak: streak, bestMonth: bestMonth, headphones: headphones, recordedDevices: recordedDevices, totalDuration: total(intervals), unattributedDuration: max(0, total(intervals) - total(identified)), activeDays: dates.count, sampleCount: valid.count, range: intervals.first.flatMap { first in intervals.last.map { DateInterval(start: first.start, end: $0.end) } }, updatedAt: now)
    }

    // Merge only touching or overlapping intervals. No gap is treated as wearing.
    private static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else { result.append(interval) }
        }
        return result
    }
    private static func total(_ intervals: [DateInterval]) -> TimeInterval { intervals.reduce(0) { $0 + $1.duration } }

    static func demo(now: Date = Date()) -> PersonalRecords {
        let calendar = Calendar.current
        var samples: [ListeningRecord] = []
        for offset in -119...0 where offset % 23 != 0 {
            let report = ListeningReport.demo(period: .day, offset: offset, now: now)
            for var sample in report.records {
                let isPro = (calendar.component(.day, from: sample.start) % 4 != 0)
                sample.device = ListeningDeviceInfo(name: isPro ? "示例 AirPods Pro" : "示例 AirPods Max", manufacturer: "Apple", model: isPro ? "AirPods Pro" : "AirPods Max", localIdentifier: isPro ? "demo-pro" : "demo-max")
                samples.append(sample)
            }
        }
        return calculate(samples, now: now)
    }
}
