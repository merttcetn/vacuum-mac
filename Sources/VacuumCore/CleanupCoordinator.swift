import Foundation

public actor CleanupCoordinator {
    private let mode: SafetyMode
    private let fileManager: FileManager
    private let processInspector: ProcessInspecting
    private let historyStore: CleanupHistoryStore

    public init(
        mode: SafetyMode,
        fileManager: FileManager = .default,
        processInspector: ProcessInspecting = ProcessInspector(),
        historyStore: CleanupHistoryStore
    ) {
        self.mode = mode
        self.fileManager = fileManager
        self.processInspector = processInspector
        self.historyStore = historyStore
    }

    public func execute(
        plan: CleanupPlan,
        operation: CleanupOperation,
        allowedRoots: [URL],
        confirmationHeldFor duration: Duration? = nil
    ) async -> [CleanupRecord] {
        guard mode == .enabled else {
            return plan.candidates.map {
                CleanupRecord(
                    originalURL: $0.url,
                    trashURL: nil,
                    operation: operation,
                    estimatedBytes: $0.allocatedSize,
                    status: .skipped,
                    detail: VacuumCoreError.readOnlyBeta.localizedDescription
                )
            }
        }

        var records: [CleanupRecord] = []
        for candidate in plan.candidates {
            let record: CleanupRecord
            do {
                if operation == .permanent, duration == nil || duration! < .milliseconds(1_500) {
                    throw VacuumCoreError.invalidCandidate("Hold for 1.5 seconds to confirm permanent cleanup.")
                }
                try FileSystemSafety.validate(
                    candidate,
                    allowedRoots: allowedRoots,
                    processInspector: processInspector
                )
                switch operation {
                case .trash:
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: candidate.url, resultingItemURL: &resultingURL)
                    record = CleanupRecord(
                        originalURL: candidate.url,
                        trashURL: resultingURL as URL?,
                        operation: .trash,
                        estimatedBytes: candidate.allocatedSize,
                        status: .moved,
                        detail: "Moved to Trash; disk space is pending reclaim."
                    )
                case .permanent:
                    try fileManager.removeItem(at: candidate.url)
                    record = CleanupRecord(
                        originalURL: candidate.url,
                        trashURL: nil,
                        operation: .permanent,
                        estimatedBytes: candidate.allocatedSize,
                        reclaimedBytes: candidate.allocatedSize,
                        status: .removed
                    )
                }
            } catch {
                record = CleanupRecord(
                    originalURL: candidate.url,
                    trashURL: nil,
                    operation: operation,
                    estimatedBytes: candidate.allocatedSize,
                    status: .skipped,
                    detail: error.localizedDescription
                )
            }
            records.append(record)
            await historyStore.append(record)
        }
        return records
    }

    public func restore(recordID: UUID) async throws -> CleanupRecord {
        guard mode == .enabled else { throw VacuumCoreError.readOnlyBeta }
        guard var record = await historyStore.record(id: recordID),
              record.operation == .trash,
              record.status == .moved,
              let trashURL = record.trashURL,
              let originalURL = record.originalURL,
              fileManager.fileExists(atPath: trashURL.path)
        else {
            throw VacuumCoreError.recordNotRestorable
        }

        let destination = collisionSafeDestination(for: originalURL)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: trashURL, to: destination)
        record.status = .restored
        record.originalURL = destination
        record.trashURL = nil
        record.detail = destination == originalURL ? "Restored" : "Restored beside an existing item"
        await historyStore.replace(record)
        return record
    }

    public func purge(recordID: UUID, confirmationHeldFor duration: Duration) async throws -> CleanupRecord {
        guard mode == .enabled else { throw VacuumCoreError.readOnlyBeta }
        guard duration >= .milliseconds(1_500) else {
            throw VacuumCoreError.invalidCandidate("Hold for 1.5 seconds to confirm.")
        }
        guard var record = await historyStore.record(id: recordID),
              record.operation == .trash,
              record.status == .moved,
              let trashURL = record.trashURL
        else {
            throw VacuumCoreError.notVacuumTrash
        }

        if fileManager.fileExists(atPath: trashURL.path) {
            try fileManager.removeItem(at: trashURL)
            record.status = .removed
            record.reclaimedBytes = record.estimatedBytes
        } else {
            record.status = .missing
            record.detail = "The item was removed from Trash outside Vacuum."
        }
        record.trashURL = nil
        await historyStore.replace(record)
        return record
    }

    public func reconcileTrash() async {
        let records = await historyStore.records()
        for var record in records where record.status == .moved {
            if let trashURL = record.trashURL, !fileManager.fileExists(atPath: trashURL.path) {
                record.status = .missing
                record.trashURL = nil
                record.detail = "The item is no longer in Trash."
                await historyStore.replace(record)
            }
        }
    }

    private func collisionSafeDestination(for original: URL) -> URL {
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let suffix = " restored \(formatter.string(from: .now))"
        let extensionName = original.pathExtension
        let base = original.deletingPathExtension().lastPathComponent
        let name = extensionName.isEmpty ? base + suffix : base + suffix + "." + extensionName
        return original.deletingLastPathComponent().appending(path: name)
    }
}
