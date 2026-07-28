import Foundation
import XCTest
@testable import VacuumCore

final class CleanupHistoryStoreTests: XCTestCase {
    func testHistoryExpiresPathDetailsAfterThirtyDays() async throws {
        let fixture = try TemporaryDirectory()
        let store = CleanupHistoryStore(fileURL: fixture.url.appending(path: "history.json"))
        let oldRecord = CleanupRecord(
            originalURL: fixture.url.appending(path: "original/cache"),
            trashURL: fixture.url.appending(path: "trash/cache"),
            operation: .trash,
            estimatedBytes: 42,
            status: .moved,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        await store.append(oldRecord)

        let records = await store.records(
            now: Date(timeIntervalSince1970: 1_000 + (31 * 24 * 60 * 60))
        )

        XCTAssertNil(records[0].originalURL)
        XCTAssertNil(records[0].trashURL)
        XCTAssertEqual(records[0].status, .moved)
        XCTAssertTrue(records[0].detail?.contains("expired") == true)
    }

    func testHistoryPersistsAndLoadsRecords() async throws {
        let fixture = try TemporaryDirectory()
        let fileURL = fixture.url.appending(path: "history.json")
        let firstStore = CleanupHistoryStore(fileURL: fileURL)
        let record = CleanupRecord(
            originalURL: fixture.url.appending(path: "cache"),
            trashURL: nil,
            operation: .permanent,
            estimatedBytes: 100,
            reclaimedBytes: 100,
            status: .removed
        )
        await firstStore.append(record)

        let secondStore = CleanupHistoryStore(fileURL: fileURL)
        let loaded = await secondStore.record(id: record.id)

        XCTAssertEqual(loaded, record)
    }
}
