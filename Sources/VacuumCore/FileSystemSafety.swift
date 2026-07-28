import Darwin
import Foundation

public enum FileSystemSafety {
    public static func identity(at url: URL) throws -> ResourceIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw VacuumCoreError.invalidCandidate("The item is no longer accessible.")
        }
        guard (info.st_mode & S_IFMT) != S_IFLNK else {
            throw VacuumCoreError.invalidCandidate("Symbolic links are never followed.")
        }
        return ResourceIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    public static func validate(
        _ candidate: CacheCandidate,
        allowedRoots: [URL],
        processInspector: ProcessInspecting
    ) throws {
        let target = candidate.url.standardizedFileURL
        guard let root = allowedRoots
            .map(\.standardizedFileURL)
            .filter({ contains(target, in: $0) })
            .max(by: { $0.path.count < $1.path.count })
        else {
            throw VacuumCoreError.invalidCandidate("The path is outside an approved root.")
        }

        try rejectSymlinkComponents(from: root, through: target)
        var info = stat()
        guard lstat(target.path, &info) == 0 else {
            throw VacuumCoreError.invalidCandidate("The item changed or disappeared.")
        }
        guard info.st_uid == getuid() else {
            throw VacuumCoreError.invalidCandidate("The item is not owned by the current user.")
        }
        let current = ResourceIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
        guard current == candidate.resourceIdentity else {
            throw VacuumCoreError.invalidCandidate("The resource identity changed after scanning.")
        }
        if let running = processInspector.firstRunning(in: candidate.processGuard) {
            throw VacuumCoreError.processRunning(running)
        }
    }

    public static func contains(_ child: URL, in root: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private static func rejectSymlinkComponents(from root: URL, through target: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard targetPath != rootPath else {
            _ = try identity(at: target)
            return
        }

        let suffix = String(targetPath.dropFirst(rootPath.count))
        var current = root
        _ = try identity(at: current)
        for component in suffix.split(separator: "/") {
            current.append(path: String(component))
            _ = try identity(at: current)
        }
    }
}

public protocol ProcessInspecting: Sendable {
    func firstRunning(in names: Set<String>) -> String?
}

public struct ProcessInspector: ProcessInspecting, Sendable {
    public init() {}

    public func firstRunning(in names: Set<String>) -> String? {
        guard !names.isEmpty else { return nil }
        let lowered = Self.normalizedNames(names)
        var pids = [pid_t](repeating: 0, count: 4_096)
        let processCount = proc_listallpids(
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard processCount > 0 else { return nil }

        for pid in pids.prefix(Int(processCount)) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let process = String(
                decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                as: UTF8.self
            ).lowercased()
            if let original = lowered.first(where: {
                process == $0.key || process.contains($0.key)
            })?.value {
                return original
            }
        }
        return nil
    }

    static func normalizedNames(_ names: Set<String>) -> [String: String] {
        var normalized: [String: String] = [:]
        for name in names.sorted() {
            let key = name.lowercased()
            if normalized[key] == nil {
                normalized[key] = name
            }
        }
        return normalized
    }
}
