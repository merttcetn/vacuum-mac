import XCTest
@testable import VacuumCore

final class ModelTests: XCTestCase {
    func testOnlySafeCandidatesAreSelectedByDefault() throws {
        let fixture = try TemporaryDirectory()
        let safe = try candidate(at: fixture.directory("safe"), risk: .safe)
        let review = try candidate(at: fixture.directory("review"), risk: .review)
        let protected = try candidate(at: fixture.directory("protected"), risk: .protected)

        XCTAssertTrue(safe.isSelected)
        XCTAssertFalse(review.isSelected)
        XCTAssertFalse(protected.isSelected)
    }

    func testCleanupPlanCopiesOnlySelectedNonProtectedCandidates() throws {
        let fixture = try TemporaryDirectory()
        let safe = try candidate(at: fixture.directory("safe"), risk: .safe)
        let unselected = try candidate(
            at: fixture.directory("unselected"),
            risk: .review,
            selected: false
        )
        let forcedProtected = try candidate(
            at: fixture.directory("protected"),
            risk: .protected,
            selected: true
        )

        let plan = CleanupPlan(candidates: [safe, unselected, forcedProtected])

        XCTAssertEqual(plan.candidates.map(\.url), [safe.url])
    }

    func testSnapshotTotalsAndSelectedBytesRemainSeparatedByRisk() throws {
        let fixture = try TemporaryDirectory()
        let safeURL = try fixture.directory("safe")
        let reviewURL = try fixture.directory("review")
        let safe = CacheCandidate(
            ruleID: "safe",
            url: safeURL,
            resourceIdentity: try FileSystemSafety.identity(at: safeURL),
            allocatedSize: 10,
            lastModified: .now,
            risk: .safe,
            reason: "",
            rebuildImpact: ""
        )
        let review = CacheCandidate(
            ruleID: "review",
            url: reviewURL,
            resourceIdentity: try FileSystemSafety.identity(at: reviewURL),
            allocatedSize: 20,
            lastModified: .now,
            risk: .review,
            reason: "",
            rebuildImpact: "",
            isSelected: true
        )
        let snapshot = ScanSnapshot(
            volume: VolumeSnapshot(name: "Test", totalBytes: 100, availableBytes: 50),
            candidates: [safe, review]
        )

        XCTAssertEqual(snapshot.total(for: .safe), 10)
        XCTAssertEqual(snapshot.total(for: .review), 20)
        XCTAssertEqual(snapshot.total(for: .protected), 0)
        XCTAssertEqual(snapshot.selectedBytes, 30)
    }
}
