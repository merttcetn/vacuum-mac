import Darwin
import Foundation
import XCTest
@testable import VacuumCore

final class ScanCoordinatorTests: XCTestCase {
    func testProjectArtifactsRequireTheMatchingManifestOrLockfile() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let projects = try fixture.directory("projects")
        let validFixtures: [(String, String)] = [
            ("node/node_modules", "node/package-lock.json"),
            ("swift/.build", "swift/Package.swift"),
            ("dart/.dart_tool", "dart/pubspec.lock"),
            ("python/.venv", "python/pyproject.toml"),
            ("python-legacy/venv", "python-legacy/requirements.txt"),
            ("cocoapods/Pods", "cocoapods/Podfile.lock")
        ]
        for (artifact, manifest) in validFixtures {
            try fixture.directory("projects/\(artifact)")
            try fixture.file("projects/\(manifest)")
        }
        try fixture.directory("projects/unverified/node_modules")
        try fixture.file("projects/unverified/README.md")

        let snapshot = try await ScanCoordinator(processInspector: StubProcessInspector())
            .scan(configuration: scanConfiguration(home: home, projectRoots: [projects]))
        let projectCandidates = snapshot.candidates.filter { $0.ruleID == "projects.artifacts" }

        XCTAssertEqual(Set(projectCandidates.map(\.url.lastPathComponent)), [
            "node_modules", ".build", ".dart_tool", ".venv", "venv", "Pods"
        ])
        XCTAssertTrue(projectCandidates.allSatisfy { $0.risk == .review && !$0.isSelected })
        XCTAssertFalse(projectCandidates.contains {
            $0.url.path.contains("unverified")
        })
    }

    func testCodexProfilesOnlyExposeExplicitCacheAllowlist() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let primary = try fixture.directory("home/.codex")
        let secondary = try fixture.directory("home/.codex-mastersoft")

        let protectedPaths = [
            "auth.json", "config.toml", "sessions/session.jsonl", "history.jsonl",
            "skills/example/SKILL.md", "plugins/plugin.json", "packages/index.json",
            "state_5.sqlite", "state.sqlite", "outputs/result.txt"
        ]
        for profile in [primary, secondary] {
            for relativePath in protectedPaths {
                let relative = profile.path.replacingOccurrences(of: fixture.url.path + "/", with: "")
                try fixture.file("\(relative)/\(relativePath)")
            }
        }

        let oldCache = try fixture.directory("home/.codex/cache")
        let oldTemporary = try fixture.directory("home/.codex-mastersoft/.tmp")
        try fixture.age(oldCache, days: 8)
        try fixture.age(oldTemporary, days: 8)

        let snapshot = try await ScanCoordinator(processInspector: StubProcessInspector())
            .scan(configuration: scanConfiguration(
                home: home,
                codexProfiles: [primary, secondary]
            ))
        let codex = snapshot.candidates.filter { $0.ruleID == "codex.profile" }

        XCTAssertEqual(Set(codex.map {
            "\($0.url.deletingLastPathComponent().lastPathComponent)/\($0.url.lastPathComponent)"
        }), [".codex/cache", ".codex-mastersoft/.tmp"])
        XCTAssertTrue(codex.allSatisfy { $0.risk == .review && !$0.isSelected })
        for protectedPath in protectedPaths {
            XCTAssertFalse(codex.contains { $0.url.path.hasSuffix(protectedPath) })
        }
    }

    func testIncompleteRuntimeIsSafeAndActiveRuntimeIsProtected() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let incompleteProfile = try fixture.directory("home/.codex-incomplete")
        let activeProfile = try fixture.directory("home/.codex-active")
        try fixture.directory("home/.codex-incomplete/runtimes")
        try fixture.file("home/.codex-incomplete/runtimes/.incomplete")
        try fixture.directory("home/.codex-active/runtimes")

        let snapshot = try await ScanCoordinator(processInspector: StubProcessInspector())
            .scan(configuration: scanConfiguration(
                home: home,
                codexProfiles: [incompleteProfile, activeProfile]
            ))
        let risks = Dictionary(
            uniqueKeysWithValues: snapshot.candidates
                .filter { $0.ruleID == "codex.profile" }
                .map {
                    (
                        "\($0.url.deletingLastPathComponent().lastPathComponent)/\($0.url.lastPathComponent)",
                        $0.risk
                    )
                }
        )

        XCTAssertEqual(risks[".codex-incomplete/runtimes"], .safe)
        XCTAssertEqual(risks[".codex-active/runtimes"], .protected)
    }

    func testProcessGuardProtectsCandidateAndClearsDefaultSelection() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let npm = try fixture.directory("home/.npm/_cacache")
        _ = try fixture.file(
            "home/.npm/_cacache/payload",
            contents: Data(repeating: 0x5A, count: 4_096)
        )

        let snapshot = try await ScanCoordinator(
            processInspector: StubProcessInspector(running: "npm")
        ).scan(configuration: scanConfiguration(home: home))
        let npmCandidate = try XCTUnwrap(snapshot.candidates.first { $0.url == npm })

        XCTAssertEqual(npmCandidate.risk, .protected)
        XCTAssertFalse(npmCandidate.isSelected)
        XCTAssertTrue(npmCandidate.reason.contains("running"))
        XCTAssertGreaterThan(npmCandidate.allocatedSize, 0)
    }

    func testProgressCountsCompletedCandidatesMonotonically() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        try fixture.directory("home/.npm/_cacache")
        try fixture.directory("home/.cache/uv")
        let recorder = ScanProgressRecorder()

        let snapshot = try await ScanCoordinator(processInspector: StubProcessInspector())
            .scan(configuration: scanConfiguration(home: home)) { progress in
                await recorder.append(progress)
            }
        let updates = await recorder.updates

        XCTAssertEqual(snapshot.candidates.count, 2)
        XCTAssertEqual(updates.map(\.completed), [0, 1, 2, 2])
        XCTAssertTrue(updates.allSatisfy { $0.total == 2 })
        XCTAssertEqual(updates.last?.currentPath, "Complete")
    }

    func testXcodeUsesAgeThresholdAndModelsAlwaysRequireReview() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let derivedData = try fixture.directory("home/Library/Developer/Xcode/DerivedData")
        let oldProject = try fixture.directory(
            "home/Library/Developer/Xcode/DerivedData/OldProject-a"
        )
        let newProject = try fixture.directory(
            "home/Library/Developer/Xcode/DerivedData/NewProject-b"
        )
        try fixture.file(
            "home/Library/Developer/Xcode/DerivedData/OldProject-a/info.plist"
        )
        try fixture.file(
            "home/Library/Developer/Xcode/DerivedData/NewProject-b/info.plist"
        )
        let globalModuleCache = try fixture.directory(
            "home/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"
        )
        try fixture.age(oldProject, days: 8)
        try fixture.age(newProject, days: 1)
        let model = try fixture.directory("home/.cache/huggingface/hub/model-a")
        _ = derivedData

        let snapshot = try await ScanCoordinator(processInspector: StubProcessInspector())
            .scan(configuration: scanConfiguration(home: home))
        let byName = Dictionary(uniqueKeysWithValues: snapshot.candidates.map {
            ($0.url.lastPathComponent, $0)
        })

        XCTAssertEqual(byName[oldProject.lastPathComponent]?.risk, .safe)
        XCTAssertEqual(byName[newProject.lastPathComponent]?.risk, .review)
        XCTAssertEqual(byName[model.lastPathComponent]?.risk, .review)
        XCTAssertEqual(byName[model.lastPathComponent]?.isSelected, false)
        XCTAssertNil(byName[globalModuleCache.lastPathComponent])
    }

    func testPlaywrightProtectsNewestAndReferencedRevisions() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let cache = try fixture.directory("home/Library/Caches/ms-playwright")
        let oldest = try fixture.directory("home/Library/Caches/ms-playwright/chromium-1000")
        let referenced = try fixture.directory("home/Library/Caches/ms-playwright/chromium-1100")
        let newest = try fixture.directory("home/Library/Caches/ms-playwright/chromium-1200")
        let ambiguous = try fixture.directory("home/Library/Caches/ms-playwright/chromium-old")
        try fixture.file(
            "home/Library/Caches/ms-playwright/.links/project",
            contents: Data("chromium-1100".utf8)
        )
        _ = cache

        let snapshot = try await ScanCoordinator(processInspector: StubProcessInspector())
            .scan(configuration: scanConfiguration(home: home))
        let byName = Dictionary(uniqueKeysWithValues: snapshot.candidates.map {
            ($0.url.lastPathComponent, $0.risk)
        })

        XCTAssertEqual(byName[oldest.lastPathComponent], .safe)
        XCTAssertEqual(byName[referenced.lastPathComponent], .protected)
        XCTAssertEqual(byName[newest.lastPathComponent], .protected)
        XCTAssertEqual(byName[ambiguous.lastPathComponent], .review)
    }

    func testHardlinksAreCountedOnceWithinCandidate() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let project = try fixture.directory("project")
        try fixture.file("project/package-lock.json")
        let artifact = try fixture.directory("project/node_modules")
        let first = try fixture.file(
            "project/node_modules/payload",
            contents: Data(repeating: 0x5A, count: 32 * 1_024)
        )
        let second = artifact.appending(path: "payload-copy")
        XCTAssertEqual(link(first.path, second.path), 0)

        let rootValues = try artifact.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
        ])
        let fileValues = try first.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
        ])
        let rootBytes = rootValues.totalFileAllocatedSize ?? rootValues.fileAllocatedSize ?? 0
        let fileBytes = fileValues.totalFileAllocatedSize ?? fileValues.fileAllocatedSize ?? 0
        let expected = Int64(rootBytes + fileBytes)

        let snapshot = try await ScanCoordinator(processInspector: StubProcessInspector())
            .scan(configuration: scanConfiguration(home: home, projectRoots: [project]))
        let result = try XCTUnwrap(snapshot.candidates.first {
            $0.url.path.hasSuffix("/project/node_modules")
        })

        XCTAssertEqual(result.allocatedSize, expected)
    }

    func testCancelledScanStopsWithinOneSecond() async throws {
        let fixture = try TemporaryDirectory()
        let home = try fixture.directory("home")
        let projects = try fixture.directory("projects")
        for index in 0..<512 {
            try fixture.directory("projects/project-\(index)/Sources/Feature")
        }
        let coordinator = ScanCoordinator(processInspector: StubProcessInspector())
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try await coordinator.scan(
                configuration: scanConfiguration(home: home, projectRoots: [projects])
            )
        }

        task.cancel()
        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(1))
    }
}

private actor ScanProgressRecorder {
    private(set) var updates: [ScanProgress] = []

    func append(_ progress: ScanProgress) {
        updates.append(progress)
    }
}
