import Foundation

@main
enum ListeningModelChecks {
    static func main() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 23, minute: 0))!
        for period in ListeningPeriod.allCases {
            let current = period.interval(offset: 0, now: now)
            let previous = period.interval(offset: -1, now: now)
            precondition(current.start <= now && now < current.end, "Current interval must contain now")
            if period != .all { precondition(previous.end == current.start, "Adjacent periods must meet without gaps") }
            else { precondition(previous == current, "All-history has no previous period") }
            let report = ListeningReport.demo(period: period, offset: 0, now: now)
            precondition(report.hasExposure, "Demo must contain real intervals")
            precondition(report.records.allSatisfy { $0.end <= now && $0.end > $0.start }, "No future or negative-duration records")
            precondition(report.points.allSatisfy { $0.date >= current.start && $0.date < current.end }, "No extra boundary bucket")
            precondition(report.activeDays == Set(report.records.map { Calendar.current.startOfDay(for: $0.start) }).count, "Year and all-history record days are calendar days, not monthly bucket counts")
            let duration = report.points.compactMap { $0.duration }.reduce(0, +)
            precondition(abs(duration - (report.duration ?? 0)) < 0.001, "Chart and summary durations must agree")
        }
        precondition(ListeningPeriod.year.bucketComponent == .month && ListeningPeriod.all.bucketComponent == .month)
        let earliest = Calendar.current.date(byAdding: .year, value: -12, to: now)!
        let allHistory = ListeningPeriod.all.interval(offset: 0, now: now, earliest: earliest)
        precondition(allHistory.start <= earliest && allHistory.end > now, "All-history must include records older than a preset lookback")
        let yesterday = ListeningReport.demo(period: .day, offset: -1, now: now)
        precondition(yesterday.records.count == 8)
        let duration = yesterday.records.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let energy = yesterday.records.reduce(0) { $0 + pow(10, $1.level / 10) * $1.end.timeIntervalSince($1.start) }
        precondition(abs(10 * log10(energy / duration) - yesterday.averageLevel!) < 0.000001, "Decibels must be energy weighted")
        precondition(ListeningFormat.duration(nil) == "—", "Missing data must not become zero")
        precondition(ListeningFormat.duration(30) == "不足 1 分钟")
        precondition(ListeningFormat.duration(3600) == "1 小时 0 分")
        precondition(ListeningFormat.level(nil) == "—")
        let pods = ListeningDeviceInfo(name: "Renamed", manufacturer: "Apple", model: "0x202d", localIdentifier: "pods")
        let otherPods = ListeningDeviceInfo(name: "Renamed", manufacturer: "Apple", model: "0x202d", localIdentifier: "other")
        let base = now.addingTimeInterval(-3600)
        func sample(_ start: Double, _ end: Double, level: Double = 70, device: ListeningDeviceInfo? = pods, source: String = "source") -> ListeningRecord {
            ListeningRecord(id: UUID(), start: base.addingTimeInterval(start), end: base.addingTimeInterval(end), level: level, source: source, device: device)
        }
        let minuteSamples = (0..<30).map { sample(Double($0 * 60), Double(($0 + 1) * 60)) }
        let continuous = ListeningSession.grouped(minuteSamples.reversed(), now: now)
        precondition(continuous.count == 1 && continuous[0].sampleCount == 30 && continuous[0].duration == 1800, "Thirty minute samples must be one complete session")
        precondition(ListeningSession.grouped([sample(0,60), sample(61,121)], now: now).count == 2, "Do not fabricate coverage across a gap")
        precondition(ListeningSession.grouped([sample(0,60), sample(60,120,device:otherPods)], now: now).count == 2, "Different devices must not merge")
        precondition(ListeningSession.grouped([sample(0,60), sample(60,120,source:"other")], now: now).count == 2, "Different sources must not merge")
        let overlap = ListeningSession.grouped([sample(0,120), sample(60,180)], now: now)
        precondition(overlap.count == 1 && overlap[0].duration == 180)
        let identical = minuteSamples + minuteSamples
        precondition(ListeningSession.grouped(identical, now: now)[0].sampleCount == 30)
        let energySession = ListeningSession.grouped([sample(0,60,level:60),sample(60,120,level:80)],now:now)[0]
        precondition(abs(energySession.level - 10 * log10((pow(10,6)+pow(10,8))/2)) < 0.000001)
        let clippedSession = ListeningSession.grouped(minuteSamples, within: DateInterval(start:base.addingTimeInterval(600),end:base.addingTimeInterval(1200)), now:now)
        precondition(clippedSession.count == 1 && clippedSession[0].duration == 600)
        print("PASS: period boundaries, chart totals, future-data exclusion, energy weighting, missing-data formatting")
        print("PASS: minute sample grouping, device/source boundaries, gaps, duplicate samples, overlap duration, session energy, period clipping")
    }
}
