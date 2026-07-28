import Foundation
import XCTest
@testable import VacuumCore

final class TemporaryDirectory {
    let url: URL

    init(function: StaticString = #function) throws {
        let name = "\(function)-\(UUID().uuidString)"
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "-")
        url = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appending(path: "VacuumTests", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func directory(_ path: String) throws -> URL {
        let result = url.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    @discardableResult
    func file(_ path: String, contents: Data = Data("fixture".utf8)) throws -> URL {
        let result = url.appending(path: path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: result.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: result)
        return result
    }

    func age(_ url: URL, days: Int) throws {
        let date = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -days, to: .now)!
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }
}

struct StubProcessInspector: ProcessInspecting {
    var running: String?

    func firstRunning(in names: Set<String>) -> String? {
        guard let running, !names.isEmpty else { return nil }
        return names.contains(where: {
            $0.localizedCaseInsensitiveContains(running)
                || running.localizedCaseInsensitiveContains($0)
        }) ? running : nil
    }
}

final class FailingRemovalFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

func scanConfiguration(
    home: URL,
    codexProfiles: [URL] = [],
    projectRoots: [URL] = []
) -> ScanConfiguration {
    ScanConfiguration(
        homeDirectory: home,
        codexProfiles: codexProfiles,
        projectRoots: projectRoots
    )
}

func candidate(
    at url: URL,
    risk: RiskLevel = .safe,
    selected: Bool? = nil,
    processGuard: Set<String> = []
) throws -> CacheCandidate {
    CacheCandidate(
        ruleID: "test.fixture",
        url: url,
        resourceIdentity: try FileSystemSafety.identity(at: url),
        allocatedSize: 4_096,
        lastModified: .now,
        risk: risk,
        reason: "Test fixture",
        rebuildImpact: "Recreate the fixture.",
        processGuard: processGuard,
        isSelected: selected
    )
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
