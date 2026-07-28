import Darwin
import Foundation

public actor ScanCoordinator {
    private let fileManager: FileManager
    private let processInspector: ProcessInspecting

    public init(
        fileManager: FileManager = .default,
        processInspector: ProcessInspecting = ProcessInspector()
    ) {
        self.fileManager = fileManager
        self.processInspector = processInspector
    }

    public func quickDiscovery(configuration: ScanConfiguration) -> [URL] {
        RuleCatalog.builtIn(configuration: configuration)
            .map(\.root)
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func scan(
        configuration: ScanConfiguration,
        progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }
    ) async throws -> ScanSnapshot {
        let rules = RuleCatalog.builtIn(configuration: configuration)
        var discovered: [(CacheRule, URL, RiskLevel)] = []

        for rule in rules {
            try Task.checkCancellation()
            if rule.discovery == .projectArtifacts {
                discovered += try discoverProjectArtifacts(rule: rule)
            } else {
                discovered += try discover(rule: rule)
            }
        }

        let ledger = IdentityLedger()
        var candidates: [CacheCandidate] = []
        candidates.reserveCapacity(discovered.count)
        let total = discovered.count

        try await withThrowingTaskGroup(of: CacheCandidate?.self) { group in
            for (index, item) in discovered.enumerated() {
                group.addTask { [processInspector] in
                    try Task.checkCancellation()
                    await progress(ScanProgress(completed: index, total: total, currentPath: item.1.path))
                    if let running = processInspector.firstRunning(in: item.0.processGuard) {
                        return try await Self.measureCandidate(
                            rule: item.0,
                            url: item.1,
                            risk: .protected,
                            ledger: ledger,
                            reason: "Protected because \(running) is running."
                        )
                    }
                    return try await Self.measureCandidate(
                        rule: item.0,
                        url: item.1,
                        risk: item.2,
                        ledger: ledger
                    )
                }
            }
            for try await candidate in group {
                if let candidate {
                    candidates.append(candidate)
                }
            }
        }

        await progress(ScanProgress(completed: total, total: total, currentPath: "Complete"))
        candidates.sort {
            if $0.risk != $1.risk {
                return Self.riskOrder($0.risk) < Self.riskOrder($1.risk)
            }
            return $0.allocatedSize > $1.allocatedSize
        }
        return ScanSnapshot(volume: volumeSnapshot(for: configuration.homeDirectory), candidates: candidates)
    }

    private func discover(rule: CacheRule) throws -> [(CacheRule, URL, RiskLevel)] {
        guard fileManager.fileExists(atPath: rule.root.path) else { return [] }
        switch rule.discovery {
        case .exact:
            return [(rule, rule.root, rule.defaultRisk)]
        case .children:
            return try childDirectories(of: rule.root).map { child in
                let age = Date.now.timeIntervalSince(modificationDate(of: child))
                let risk: RiskLevel
                if rule.id == "xcode.deriveddata" {
                    risk = age >= (rule.minimumAge ?? 0) ? .safe : .review
                } else {
                    risk = .review
                }
                return (rule, child, risk)
            }
        case .codexProfile:
            return try discoverCodex(rule: rule)
        case .playwright:
            return try discoverPlaywright(rule: rule)
        case .projectArtifacts:
            return []
        }
    }

    private func discoverCodex(rule: CacheRule) throws -> [(CacheRule, URL, RiskLevel)] {
        let protectedNames: Set<String> = [
            "auth.json", "config.toml", "sessions", "history.jsonl", "skills",
            "plugins", "packages", "state_5.sqlite", "state.sqlite", "outputs"
        ]
        let allowedNames: Set<String> = [".tmp", "cache", "cachedir", "runtimes"]
        let children = try fileManager.contentsOfDirectory(
            at: rule.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        return children.compactMap { child in
            let name = child.lastPathComponent
            guard !protectedNames.contains(name), allowedNames.contains(name) else { return nil }
            let age = Date.now.timeIntervalSince(modificationDate(of: child))
            if name == "runtimes" {
                let incompleteMarkers = [".incomplete", "INCOMPLETE", "download.incomplete"]
                if incompleteMarkers.contains(where: {
                    fileManager.fileExists(atPath: child.appending(path: $0).path)
                }) {
                    return (rule, child, .safe)
                }
                let runtimeChildren = (try? childDirectories(of: child)) ?? []
                return runtimeChildren.isEmpty ? (rule, child, .protected) : nil
            }
            guard age >= (rule.minimumAge ?? 0) else { return nil }
            return (rule, child, .review)
        } + discoverCodexRuntimes(rule: rule)
    }

    private func discoverCodexRuntimes(rule: CacheRule) -> [(CacheRule, URL, RiskLevel)] {
        let runtimes = rule.root.appending(path: "runtimes", directoryHint: .isDirectory)
        guard let children = try? childDirectories(of: runtimes) else { return [] }
        let rootMarkers = [".incomplete", "INCOMPLETE", "download.incomplete"]
        guard !rootMarkers.contains(where: {
            fileManager.fileExists(atPath: runtimes.appending(path: $0).path)
        }) else { return [] }
        let sorted = children.sorted { modificationDate(of: $0) > modificationDate(of: $1) }
        return sorted.compactMap { runtime in
            let incompleteMarkers = [".incomplete", "INCOMPLETE", "download.incomplete"]
            if incompleteMarkers.contains(where: {
                fileManager.fileExists(atPath: runtime.appending(path: $0).path)
            }) {
                return (rule, runtime, .safe)
            }
            if runtime == sorted.first {
                return (rule, runtime, .protected)
            }
            let age = Date.now.timeIntervalSince(modificationDate(of: runtime))
            return age >= (rule.minimumAge ?? 0) ? (rule, runtime, .review) : nil
        }
    }

    private func discoverPlaywright(rule: CacheRule) throws -> [(CacheRule, URL, RiskLevel)] {
        let children = try childDirectories(of: rule.root)
            .filter { $0.lastPathComponent != ".links" }
        let linkedText: String = {
            let links = rule.root.appending(path: ".links")
            guard let enumerator = fileManager.enumerator(at: links, includingPropertiesForKeys: nil) else {
                return ""
            }
            return enumerator.compactMap { element -> String? in
                guard let url = element as? URL else { return nil }
                return try? String(contentsOf: url, encoding: .utf8)
            }.joined(separator: "\n")
        }()

        let grouped = Dictionary(grouping: children) {
            $0.lastPathComponent.split(separator: "-").first.map(String.init) ?? $0.lastPathComponent
        }
        return grouped.values.flatMap { revisions in
            let numericRevisions: [(url: URL, revision: Int)] = revisions.compactMap { url in
                guard let suffix = url.lastPathComponent.split(separator: "-").last,
                      let revision = Int(suffix)
                else { return nil }
                return (url, revision)
            }
            let newestRevision = numericRevisions.map(\.revision).max()
            return revisions.map { revision in
                let referenced = linkedText.contains(revision.lastPathComponent)
                let numericRevision = numericRevisions.first { $0.url == revision }?.revision
                let risk: RiskLevel
                if referenced || (numericRevision != nil && numericRevision == newestRevision) {
                    risk = .protected
                } else {
                    risk = numericRevision == nil ? .review : .safe
                }
                return (rule, revision, risk)
            }
        }
    }

    private func discoverProjectArtifacts(rule: CacheRule) throws -> [(CacheRule, URL, RiskLevel)] {
        let names: Set<String> = ["node_modules", ".build", ".dart_tool", ".venv", "venv", "Pods"]
        let skip: Set<String> = [".git", ".svn", ".hg", "Library", "DerivedData"]
        var results: [(CacheRule, URL, RiskLevel)] = []
        guard let enumerator = fileManager.enumerator(
            at: rule.root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited % 128 == 0 { try Task.checkCancellation() }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true else { continue }
            if values?.isSymbolicLink == true || skip.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard names.contains(url.lastPathComponent) else { continue }
            enumerator.skipDescendants()
            if validatesProjectArtifact(url) {
                results.append((rule, url, .review))
            }
        }
        return results
    }

    private func validatesProjectArtifact(_ artifact: URL) -> Bool {
        let project = artifact.deletingLastPathComponent()
        let required: [String]
        switch artifact.lastPathComponent {
        case "node_modules":
            required = ["package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb"]
        case ".build":
            required = ["Package.swift", "Package.resolved"]
        case ".dart_tool":
            required = ["pubspec.yaml", "pubspec.lock"]
        case ".venv", "venv":
            required = ["pyproject.toml", "uv.lock", "requirements.txt", "Pipfile.lock", "poetry.lock"]
        case "Pods":
            required = ["Podfile", "Podfile.lock"]
        default:
            return false
        }
        return required.contains { fileManager.fileExists(atPath: project.appending(path: $0).path) }
    }

    private func childDirectories(of root: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter {
            let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func volumeSnapshot(for url: URL) -> VolumeSnapshot {
        let values = try? url.resourceValues(forKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ])
        return VolumeSnapshot(
            name: values?.volumeName ?? "Macintosh HD",
            totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
            availableBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    nonisolated private static func measureCandidate(
        rule: CacheRule,
        url: URL,
        risk: RiskLevel,
        ledger: IdentityLedger,
        reason: String? = nil
    ) async throws -> CacheCandidate {
        let identity = try FileSystemSafety.identity(at: url)
        let size = try await DirectorySizer.measure(url, ledger: ledger)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return CacheCandidate(
            ruleID: rule.id,
            url: url,
            resourceIdentity: identity,
            allocatedSize: size,
            lastModified: modified,
            risk: risk,
            reason: reason
                ?? (risk == .protected
                    ? "Protected while active or required by the newest revision"
                    : rule.reason),
            rebuildImpact: rule.rebuildImpact,
            processGuard: rule.processGuard
        )
    }

    nonisolated private static func riskOrder(_ risk: RiskLevel) -> Int {
        switch risk {
        case .safe: 0
        case .review: 1
        case .protected: 2
        }
    }
}

private actor IdentityLedger {
    private var seen: Set<ResourceIdentity> = []

    func claim(_ identity: ResourceIdentity) -> Bool {
        seen.insert(identity).inserted
    }
}

private enum DirectorySizer {
    static func measure(_ root: URL, ledger: IdentityLedger) async throws -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]
        var total: Int64 = 0
        var processed = 0

        func count(_ url: URL) async throws {
            let identity = try FileSystemSafety.identity(at: url)
            guard await ledger.claim(identity) else { return }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { return }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        try await count(root)
        for url in try collectURLs(below: root, keys: keys) {
            processed += 1
            if processed % 128 == 0 { try Task.checkCancellation() }
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                continue
            }
            try await count(url)
        }
        return total
    }

    private static func collectURLs(below root: URL, keys: Set<URLResourceKey>) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        var visited = 0
        while let element = enumerator.nextObject() {
            visited += 1
            if visited % 128 == 0 { try Task.checkCancellation() }
            guard let url = element as? URL else { continue }
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            urls.append(url)
        }
        return urls
    }
}
