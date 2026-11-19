import Foundation

@MainActor
private final class ReportRequests {
    struct Request {
        let period: ListeningPeriod
        let offset: Int
        let continuation: CheckedContinuation<ListeningReport, Error>
    }
    var requests: [Request] = []
    func load(_ period: ListeningPeriod, _ offset: Int) async throws -> ListeningReport {
        try await withCheckedThrowingContinuation { requests.append(Request(period: period, offset: offset, continuation: $0)) }
    }
}

@MainActor
private final class HistoryRequests {
    var requests: [CheckedContinuation<PersonalRecords, Error>] = []
    func load() async throws -> PersonalRecords {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
}

@main
struct RefreshStateChecks {
    @MainActor
    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("Async state did not reach expected condition")
    }

    @MainActor
    static func main() async {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: "usesHealthData")
        defaults.set(true, forKey: "usesHealthData")
        defer {
            if let previousMode = previousMode { defaults.set(previousMode, forKey: "usesHealthData") }
            else { defaults.removeObject(forKey: "usesHealthData") }
        }
        let queue = ReportRequests()
        let store = HearingStore(reportLoader: queue.load)
        let first = Task { await store.reload() }
        await waitUntil { queue.requests.count == 1 }
        let original = ListeningReport.demo(period: .week, offset: 0)
        queue.requests[0].continuation.resume(returning: original)
        await first.value
        precondition(store.report?.updatedAt == original.updatedAt)

        let refresh = Task { await store.reload() }
        await waitUntil { queue.requests.count == 2 }
        precondition(store.report?.updatedAt == original.updatedAt && store.isLoading, "Refreshing must keep visible data")
        let joined = Task { await store.reload() }
        await Task.yield()
        precondition(queue.requests.count == 2, "Overlapping refresh requests must share one query")
        refresh.cancel()
        let replacement = ListeningReport.demo(period: .week, offset: 0)
        queue.requests[1].continuation.resume(returning: replacement)
        await refresh.value
        await joined.value
        precondition(store.report?.updatedAt == replacement.updatedAt && !store.isLoading, "View cancellation must not discard completed refresh")

        let failed = Task { await store.reload() }
        await waitUntil { queue.requests.count == 3 }
        queue.requests[2].continuation.resume(throwing: NSError(domain: "RefreshTest", code: 1))
        await failed.value
        precondition(store.report?.updatedAt == replacement.updatedAt && store.errorMessage != nil, "Read failure must keep the last good same-period data")

        let stale = Task { await store.reload() }
        await waitUntil { queue.requests.count == 4 }
        store.period = .year
        let yearly = Task { await store.reload() }
        await waitUntil { queue.requests.count == 5 }
        let yearReport = ListeningReport.demo(period: .year, offset: 0)
        queue.requests[4].continuation.resume(returning: yearReport)
        await yearly.value
        queue.requests[3].continuation.resume(returning: original)
        await stale.value
        precondition(store.report?.interval == yearReport.interval, "Late result from another period must not overwrite the current report")

        let emptyRead = Task { await store.reload() }
        await waitUntil { queue.requests.count == 6 }
        let empty = ListeningReport(interval: yearReport.interval, duration: nil, averageLevel: nil, notificationCount: 0, points: [], records: [], updatedAt: Date())
        queue.requests[5].continuation.resume(returning: empty)
        await emptyRead.value
        precondition(store.report?.hasExposure == false && store.errorMessage == nil, "A successful empty query must replace old data, not mask removed or unreadable records")

        let historyQueue = HistoryRequests()
        let history = PersonalRecordsStore(loader: historyQueue.load)
        let initialHistory = Task { await history.reload(mode: .health) }
        await waitUntil { historyQueue.requests.count == 1 }
        let records = PersonalRecords.demo()
        historyQueue.requests[0].resume(returning: records)
        await initialHistory.value
        let historyRefresh = Task { await history.reload(mode: .health) }
        await waitUntil { historyQueue.requests.count == 2 }
        precondition(history.records?.sampleCount == records.sampleCount && history.isLoading)
        historyRefresh.cancel()
        historyQueue.requests[1].resume(returning: records)
        await historyRefresh.value
        precondition(history.records?.sampleCount == records.sampleCount && !history.isLoading)
        let failedHistory = Task { await history.reload(mode: .health) }
        await waitUntil { historyQueue.requests.count == 3 }
        historyQueue.requests[2].resume(throwing: NSError(domain: "RefreshTest", code: 2))
        await failedHistory.value
        precondition(history.records?.sampleCount == records.sampleCount && history.error != nil)
        let oldHistory = Task { await history.reload(mode: .health) }
        await waitUntil { historyQueue.requests.count == 4 }
        await history.reload(mode: .demo)
        let demoDate = history.records?.updatedAt
        historyQueue.requests[3].resume(returning: PersonalRecords.calculate([]))
        await oldHistory.value
        precondition(history.records?.updatedAt == demoDate && (history.records?.sampleCount ?? 0) > 0, "Old health query must not replace demonstration data")
        print("PASS: preserve visible report/history during refresh, coalesce requests, cancelled views, query failures, stale period/source results, successful empty reads")
    }
}
