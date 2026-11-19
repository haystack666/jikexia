import Foundation
import Combine

@MainActor
final class PersonalRecordsStore: ObservableObject {
    @Published private(set) var records: PersonalRecords?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var loadID = UUID()
    private var loadedMode: HearingStore.Mode?
    private var refreshMode: HearingStore.Mode?
    private var refreshTask: Task<Void, Never>?
    private let loader: () async throws -> PersonalRecords

    init(loader: (() async throws -> PersonalRecords)? = nil) {
        self.loader = loader ?? { try await HearingHealthClient().personalRecords() }
    }

    func reload(mode: HearingStore.Mode) async {
        if refreshMode == mode, let task = refreshTask {
            await task.value
            return
        }
        refreshTask?.cancel()
        let id = UUID()
        loadID = id
        // Never mix demonstration data with a different health-data context.
        if loadedMode != mode { records = nil }
        loadedMode = mode
        refreshMode = mode
        error = nil
        isLoading = true
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                if self.loadID == id {
                    self.isLoading = false
                    self.refreshTask = nil
                    self.refreshMode = nil
                }
            }
            do {
                let result: PersonalRecords
                if mode == .demo { result = await Task.detached(priority: .userInitiated) { PersonalRecords.demo() }.value }
                else { result = try await self.loader() }
                guard self.loadID == id, !Task.isCancelled else { return }
                self.records = result
            } catch {
                guard self.loadID == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }
}
