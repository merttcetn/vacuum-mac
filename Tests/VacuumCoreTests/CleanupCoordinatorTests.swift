import Foundation
import XCTest
@testable import VacuumCore

final class CleanupCoordinatorTests: XCTestCase {
    func testReadOnlyModeNeverMutatesCandidate() async throws {
        let fixture = try TemporaryDirectory()
        let root = try fixture.directory("root")
        let cache = try fixture.directory("root/cache")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let coordinator = CleanupCoordinator(
            mode: .readOnly,
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        let records = await coordinator.execute(
            plan: CleanupPlan(candidates: [try candidate(at: cache)]),
            operation: .permanent,
            allowedRoots: [root]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(records.map(\.status), [.skipped])
        XCTAssertTrue(records[0].detail?.contains("read-only beta") == true)
    }

    func testPermanentCleanupRevalidatesProcessBeforeRemoval() async throws {
        let fixture = try TemporaryDirectory()
        let root = try fixture.directory("root")
        let cache = try fixture.directory("root/cache")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            processInspector: StubProcessInspector(running: "Codex"),
            historyStore: history
        )
        let guarded = try candidate(at: cache, processGuard: ["Codex", "ChatGPT"])

        let records = await coordinator.execute(
            plan: CleanupPlan(candidates: [guarded]),
            operation: .permanent,
            allowedRoots: [root],
            confirmationHeldFor: .milliseconds(1_500)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(records.map(\.status), [.skipped])
        XCTAssertTrue(records[0].detail?.contains("Codex is running") == true)
    }

    func testPermanentCleanupRequiresHoldWithoutMutatingCandidate() async throws {
        let fixture = try TemporaryDirectory()
        let root = try fixture.directory("root")
        let cache = try fixture.directory("root/cache")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        let records = await coordinator.execute(
            plan: CleanupPlan(candidates: [try candidate(at: cache)]),
            operation: .permanent,
            allowedRoots: [root],
            confirmationHeldFor: .milliseconds(1_499)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(records[0].status, .skipped)
        XCTAssertTrue(records[0].detail?.contains("1.5 seconds") == true)
    }

    func testPermanentCleanupRemovesValidatedCandidateAndRecordsBytes() async throws {
        let fixture = try TemporaryDirectory()
        let root = try fixture.directory("root")
        let cache = try fixture.directory("root/cache")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        let records = await coordinator.execute(
            plan: CleanupPlan(candidates: [try candidate(at: cache)]),
            operation: .permanent,
            allowedRoots: [root],
            confirmationHeldFor: .milliseconds(1_500)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(records[0].status, .removed)
        XCTAssertEqual(records[0].reclaimedBytes, 4_096)
        let historyCount = await history.records().count
        XCTAssertEqual(historyCount, 1)
    }

    func testPermissionFailureSkipsWithoutMutatingCandidate() async throws {
        let fixture = try TemporaryDirectory()
        let root = try fixture.directory("root")
        let cache = try fixture.directory("root/cache")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            fileManager: FailingRemovalFileManager(),
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        let records = await coordinator.execute(
            plan: CleanupPlan(candidates: [try candidate(at: cache)]),
            operation: .permanent,
            allowedRoots: [root],
            confirmationHeldFor: .milliseconds(1_500)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(records[0].status, .skipped)
        XCTAssertTrue(records[0].detail?.isEmpty == false)
    }

    func testTrashThenRestoreRoundTrip() async throws {
        let fixture = try TemporaryDirectory()
        let root = try fixture.directory("root")
        let cache = try fixture.directory("root/cache")
        try fixture.file("root/cache/payload")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        let records = await coordinator.execute(
            plan: CleanupPlan(candidates: [try candidate(at: cache)]),
            operation: .trash,
            allowedRoots: [root]
        )
        let moved = records[0]
        let trashURL = try XCTUnwrap(moved.trashURL)
        XCTAssertEqual(moved.status, .moved)
        XCTAssertTrue(moved.detail?.contains("pending reclaim") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.path))

        let restored = try await coordinator.restore(recordID: moved.id)

        XCTAssertEqual(restored.status, .restored)
        XCTAssertEqual(restored.originalURL?.standardizedFileURL, cache.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testRestoreNeverOverwritesExistingPath() async throws {
        let fixture = try TemporaryDirectory()
        let original = try fixture.file("destination/cache", contents: Data("existing".utf8))
        let trash = try fixture.file("tracked-trash/cache", contents: Data("restored".utf8))
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let record = CleanupRecord(
            originalURL: original,
            trashURL: trash,
            operation: .trash,
            estimatedBytes: 8,
            status: .moved
        )
        await history.append(record)
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        let restored = try await coordinator.restore(recordID: record.id)

        XCTAssertEqual(try Data(contentsOf: original), Data("existing".utf8))
        let restoredURL = try XCTUnwrap(restored.originalURL)
        XCTAssertNotEqual(restoredURL, original)
        XCTAssertEqual(try Data(contentsOf: restoredURL), Data("restored".utf8))
        XCTAssertEqual(restored.status, .restored)
    }

    func testPurgeRequiresHoldAndOnlyActsOnTrackedRecord() async throws {
        let fixture = try TemporaryDirectory()
        let trash = try fixture.file("tracked-trash/cache")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let record = CleanupRecord(
            originalURL: fixture.url.appending(path: "original/cache"),
            trashURL: trash,
            operation: .trash,
            estimatedBytes: 123,
            status: .moved
        )
        await history.append(record)
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        await XCTAssertThrowsErrorAsync(
            try await coordinator.purge(
                recordID: record.id,
                confirmationHeldFor: .milliseconds(1_499)
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
        await XCTAssertThrowsErrorAsync(
            try await coordinator.purge(
                recordID: UUID(),
                confirmationHeldFor: .milliseconds(1_500)
            )
        )

        let purged = try await coordinator.purge(
            recordID: record.id,
            confirmationHeldFor: .milliseconds(1_500)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.path))
        XCTAssertEqual(purged.status, .removed)
        XCTAssertEqual(purged.reclaimedBytes, 123)
    }

    func testReconcileMarksExternallyRemovedTrashAsMissing() async throws {
        let fixture = try TemporaryDirectory()
        let trash = try fixture.file("tracked-trash/cache")
        let history = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let record = CleanupRecord(
            originalURL: fixture.url.appending(path: "original/cache"),
            trashURL: trash,
            operation: .trash,
            estimatedBytes: 123,
            status: .moved
        )
        await history.append(record)
        try FileManager.default.removeItem(at: trash)
        let coordinator = CleanupCoordinator(
            mode: .enabled,
            processInspector: StubProcessInspector(),
            historyStore: history
        )

        await coordinator.reconcileTrash()

        let storedRecord = await history.record(id: record.id)
        let reconciled = try XCTUnwrap(storedRecord)
        XCTAssertEqual(reconciled.status, .missing)
        XCTAssertNil(reconciled.trashURL)
    }
}
