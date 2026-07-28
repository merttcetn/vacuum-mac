import Foundation
import XCTest
@testable import VacuumCore

final class FileSystemSafetyTests: XCTestCase {
    func testContainsRejectsSiblingPrefixAndNormalizesTraversal() throws {
        let fixture = try TemporaryDirectory()
        let allowed = try fixture.directory("allowed")
        let sibling = try fixture.directory("allowed-elsewhere")
        let traversing = allowed.appending(path: "../allowed-elsewhere")

        XCTAssertTrue(FileSystemSafety.contains(allowed.appending(path: "child"), in: allowed))
        XCTAssertFalse(FileSystemSafety.contains(sibling, in: allowed))
        XCTAssertFalse(FileSystemSafety.contains(traversing, in: allowed))
    }

    func testIdentityRejectsSymbolicLink() throws {
        let fixture = try TemporaryDirectory()
        let target = try fixture.file("target")
        let symbolicLink = fixture.url.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: target)

        XCTAssertThrowsError(try FileSystemSafety.identity(at: symbolicLink))
    }

    func testValidationRejectsSymbolicLinkInIntermediateComponent() throws {
        let fixture = try TemporaryDirectory()
        let allowed = try fixture.directory("allowed")
        let outside = try fixture.directory("outside")
        let target = try fixture.file("outside/payload")
        let symbolicDirectory = allowed.appending(path: "redirect")
        try FileManager.default.createSymbolicLink(
            at: symbolicDirectory,
            withDestinationURL: outside
        )
        let pathThroughLink = symbolicDirectory.appending(path: "payload")
        let unsafe = CacheCandidate(
            ruleID: "test",
            url: pathThroughLink,
            resourceIdentity: try FileSystemSafety.identity(at: target),
            allocatedSize: 1,
            lastModified: .now,
            risk: .safe,
            reason: "",
            rebuildImpact: ""
        )

        XCTAssertThrowsError(try FileSystemSafety.validate(
            unsafe,
            allowedRoots: [allowed],
            processInspector: StubProcessInspector()
        ))
    }

    func testValidationRejectsPathOutsideAllowedRoot() throws {
        let fixture = try TemporaryDirectory()
        let allowed = try fixture.directory("allowed")
        let outside = try fixture.directory("outside")
        let unsafe = try candidate(at: outside)

        XCTAssertThrowsError(try FileSystemSafety.validate(
            unsafe,
            allowedRoots: [allowed],
            processInspector: StubProcessInspector()
        ))
    }

    func testValidationRejectsResourceIdentitySwap() throws {
        let fixture = try TemporaryDirectory()
        let allowed = try fixture.directory("allowed")
        let target = try fixture.directory("allowed/cache")
        let scanned = try candidate(at: target)
        let moved = allowed.appending(path: "old-cache")
        try FileManager.default.moveItem(at: target, to: moved)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)

        XCTAssertThrowsError(try FileSystemSafety.validate(
            scanned,
            allowedRoots: [allowed],
            processInspector: StubProcessInspector()
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("identity changed"))
        }
    }

    func testValidationRechecksProcessGuard() throws {
        let fixture = try TemporaryDirectory()
        let allowed = try fixture.directory("allowed")
        let target = try fixture.directory("allowed/cache")
        let guarded = try candidate(
            at: target,
            processGuard: ["Codex", "ChatGPT"]
        )

        XCTAssertThrowsError(try FileSystemSafety.validate(
            guarded,
            allowedRoots: [allowed],
            processInspector: StubProcessInspector(running: "Codex")
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("Codex is running"))
        }
    }
}
