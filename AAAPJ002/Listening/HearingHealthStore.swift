import Foundation
import HealthKit

struct HearingHealthClient {
    private let store = HKHealthStore()
    private let exposure = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure)!
    private let event = HKCategoryType.categoryType(forIdentifier: .headphoneAudioExposureEvent)!

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        guard Self.isAvailable else { throw HearingError.unavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: [exposure, event]) { completed, error in
                if let error = error { continuation.resume(throwing: error) }
                else if completed { continuation.resume() }
                else { continuation.resume(throwing: HearingError.authorizationIncomplete) }
            }
        }
    }

    func report(period: ListeningPeriod, offset: Int) async throws -> ListeningReport {
        guard Self.isAvailable else { throw HearingError.unavailable }
        let earliest: Date?
        if period == .all {
            earliest = try await readSamples(type: exposure, predicate: nil, limit: 1, ascending: true).first?.startDate
        } else { earliest = nil }
        let interval = period.interval(offset: offset, earliest: earliest ?? (period == .all ? Date() : nil))
        let predicate: NSPredicate? = period == .all ? nil : HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        async let points = readPoints(period: period, interval: interval, predicate: predicate)
        async let summary = readSummary(predicate: predicate)
        async let notifications = readSamples(type: event, predicate: predicate, limit: HKObjectQueryNoLimit)
        // Fetch the whole period before grouping. Limiting raw samples to eight
        // truncates a multi-hour session to its last few one-minute slices.
        async let latest = readSamples(type: exposure, predicate: predicate, limit: HKObjectQueryNoLimit)
        let (series, statistics, events, samples) = try await (points, summary, notifications, latest)
        let records = samples.compactMap(Self.listeningRecord)
        let now = Date()
        let sessions = ListeningSession.grouped(records, within: interval, now: now)
        return ListeningReport(interval: interval, duration: statistics?.duration()?.doubleValue(for: .second()), averageLevel: statistics?.averageQuantity()?.doubleValue(for: .decibelAWeightedSoundPressureLevel()), notificationCount: events.filter { $0.startDate >= interval.start && $0.startDate < interval.end }.count, points: series, records: records, updatedAt: now, groupedSessions: sessions)
    }

    func personalRecords() async throws -> PersonalRecords {
        guard Self.isAvailable else { throw HearingError.unavailable }
        // No date predicate: personal records cover all currently readable history.
        let samples = try await readSamples(type: exposure, predicate: nil, limit: HKObjectQueryNoLimit)
        return PersonalRecords.calculate(samples.compactMap(Self.listeningRecord))
    }

    private static func listeningRecord(_ sample: HKSample) -> ListeningRecord? {
        guard let sample = sample as? HKQuantitySample else { return nil }
        let device = sample.device.map {
            ListeningDeviceInfo(name: $0.name, manufacturer: $0.manufacturer, model: $0.model, localIdentifier: $0.localIdentifier)
        }
        return ListeningRecord(id: sample.uuid, start: sample.startDate, end: sample.endDate, level: sample.quantity.doubleValue(for: .decibelAWeightedSoundPressureLevel()), source: sample.sourceRevision.source.name, device: device, sourceID: sample.sourceRevision.source.bundleIdentifier)
    }

    private func readSummary(predicate: NSPredicate?) async throws -> HKStatistics? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: exposure, quantitySamplePredicate: predicate, options: [.discreteAverage, .duration]) { _, result, error in
                if let error = error as NSError?, error.domain == HKErrorDomain && error.code == HKError.Code.errorNoData.rawValue { continuation.resume(returning: nil) }
                else if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result) }
            }
            store.execute(query)
        }
    }

    private func readPoints(period: ListeningPeriod, interval: DateInterval, predicate: NSPredicate?) async throws -> [ListeningPoint] {
        try await withCheckedThrowingContinuation { continuation in
            var components = DateComponents()
            components.setValue(1, for: period.bucketComponent)
            let query = HKStatisticsCollectionQuery(quantityType: exposure, quantitySamplePredicate: predicate, options: [.discreteAverage, .duration], anchorDate: interval.start, intervalComponents: components)
            query.initialResultsHandler = { _, result, error in
                if let error = error as NSError?, error.domain == HKErrorDomain && error.code == HKError.Code.errorNoData.rawValue { continuation.resume(returning: []); return }
                if let error = error { continuation.resume(throwing: error); return }
                var points: [ListeningPoint] = []
                result?.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                    guard statistics.startDate < interval.end else { return }
                    points.append(ListeningPoint(date: statistics.startDate, level: statistics.averageQuantity()?.doubleValue(for: .decibelAWeightedSoundPressureLevel()), duration: statistics.duration()?.doubleValue(for: .second())))
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private func readSamples(type: HKSampleType, predicate: NSPredicate?, limit: Int, ascending: Bool = false) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}

enum HearingError: LocalizedError {
    case unavailable, authorizationIncomplete
    var errorDescription: String? {
        switch self {
        case .unavailable: return "这台设备目前无法访问健康数据。iPad 需要 iPadOS 17 或更新版本。"
        case .authorizationIncomplete: return "访问请求未完成，请稍后重试。"
        }
    }
}

@MainActor
final class HearingStore: ObservableObject {
    enum Mode: String { case demo, health }
    @Published var period: ListeningPeriod = .week {
        didSet { if period != oldValue { offset = 0; report = nil } }
    }
    @Published var offset = 0 {
        didSet { if offset != oldValue { report = nil } }
    }
    @Published private(set) var mode: Mode
    @Published private(set) var report: ListeningReport?
    @Published private(set) var isLoading = false
    @Published private(set) var isConnecting = false
    @Published var errorMessage: String?
    private let health = HearingHealthClient()
    private var loadID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var refreshKey: String?
    private let reportLoader: (ListeningPeriod, Int) async throws -> ListeningReport
    var queryKey: String { "\(mode.rawValue)-\(period.rawValue)-\(offset)" }
    var interval: DateInterval { report?.interval ?? period.interval(offset: offset) }

    init(reportLoader: ((ListeningPeriod, Int) async throws -> ListeningReport)? = nil) {
        self.reportLoader = reportLoader ?? { period, offset in
            try await HearingHealthClient().report(period: period, offset: offset)
        }
        let mode: Mode = UserDefaults.standard.bool(forKey: "usesHealthData") ? .health : .demo
        self.mode = mode
        self.report = mode == .demo ? .demo(period: .week, offset: 0) : nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            self.mode = .demo
            self.report = .demo(period: .week, offset: 0)
        }
        #endif
    }

    func showDemo() {
        loadID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        refreshKey = nil
        mode = .demo
        report = .demo(period: period, offset: offset)
        isLoading = false
        UserDefaults.standard.set(false, forKey: "usesHealthData")
        errorMessage = nil
    }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await health.requestAccess()
            // Completion confirms the request finished, not that read permission was granted.
            UserDefaults.standard.set(true, forKey: "usesHealthData")
            if mode != .health { report = nil }
            mode = .health
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        let key = queryKey
        if refreshKey == key, let task = refreshTask {
            await task.value
            return
        }
        refreshTask?.cancel()
        let id = UUID()
        loadID = id
        let requestedPeriod = period
        let requestedOffset = offset
        let requestedMode = mode
        isLoading = true
        errorMessage = nil
        refreshKey = key
        // This task belongs to the store, not to the refresh gesture/view task.
        // Cancelling a waiting view must not discard an otherwise valid result.
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                if self.loadID == id {
                    self.isLoading = false
                    self.refreshTask = nil
                    self.refreshKey = nil
                }
            }
            do {
                let result: ListeningReport
                if requestedMode == .demo { result = .demo(period: requestedPeriod, offset: requestedOffset) }
                else { result = try await self.reportLoader(requestedPeriod, requestedOffset) }
                guard self.loadID == id, self.queryKey == key, !Task.isCancelled else { return }
                self.report = result
            } catch {
                guard self.loadID == id, self.queryKey == key, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }

    var shareText: String {
        guard let report = report else { return "即刻匣 · 听音报告" }
        let source = mode == .demo ? "演示数据，非个人健康记录" : "基于可读取的健康记录"
        return "即刻匣 · 听音报告\n\(ListeningFormat.dateRange(report.interval, period: period))\n\n已记录听音：\(ListeningFormat.duration(report.duration))\n等效声级：\(ListeningFormat.level(report.averageLevel)) dBA\n系统耳机提醒：\(report.notificationCount) 次\n\n\(source)\n听音记录不等于全部佩戴时间。"
    }
}
