import Foundation

public enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case safe = "Safe"
    case review = "Review"
    case protected = "Protected"
}

public struct ResourceIdentity: Hashable, Codable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public struct CacheCandidate: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let ruleID: String
    public let url: URL
    public let resourceIdentity: ResourceIdentity
    public let allocatedSize: Int64
    public let lastModified: Date
    public let risk: RiskLevel
    public let reason: String
    public let rebuildImpact: String
    public let processGuard: Set<String>
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        ruleID: String,
        url: URL,
        resourceIdentity: ResourceIdentity,
        allocatedSize: Int64,
        lastModified: Date,
        risk: RiskLevel,
        reason: String,
        rebuildImpact: String,
        processGuard: Set<String> = [],
        isSelected: Bool? = nil
    ) {
        self.id = id
        self.ruleID = ruleID
        self.url = url
        self.resourceIdentity = resourceIdentity
        self.allocatedSize = allocatedSize
        self.lastModified = lastModified
        self.risk = risk
        self.reason = reason
        self.rebuildImpact = rebuildImpact
        self.processGuard = processGuard
        self.isSelected = isSelected ?? (risk == .safe)
    }
}

public struct VolumeSnapshot: Hashable, Codable, Sendable {
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(name: String, totalBytes: Int64, availableBytes: Int64) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}

public struct ScanSnapshot: Hashable, Codable, Sendable {
    public let volume: VolumeSnapshot
    public let candidates: [CacheCandidate]
    public let scannedAt: Date

    public init(volume: VolumeSnapshot, candidates: [CacheCandidate], scannedAt: Date = .now) {
        self.volume = volume
        self.candidates = candidates
        self.scannedAt = scannedAt
    }

    public func total(for risk: RiskLevel) -> Int64 {
        candidates.lazy.filter { $0.risk == risk }.reduce(0) { $0 + $1.allocatedSize }
    }

    public var selectedBytes: Int64 {
        candidates.lazy.filter(\.isSelected).reduce(0) { $0 + $1.allocatedSize }
    }
}

public struct ScanProgress: Hashable, Sendable {
    public let completed: Int
    public let total: Int
    public let currentPath: String

    public init(completed: Int, total: Int, currentPath: String) {
        self.completed = completed
        self.total = total
        self.currentPath = currentPath
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

public struct ScanConfiguration: Sendable {
    public let homeDirectory: URL
    public let codexProfiles: [URL]
    public let projectRoots: [URL]

    public init(homeDirectory: URL, codexProfiles: [URL], projectRoots: [URL]) {
        self.homeDirectory = homeDirectory
        self.codexProfiles = codexProfiles
        self.projectRoots = projectRoots
    }
}

public struct CleanupPlan: Hashable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let candidates: [CacheCandidate]

    public init(id: UUID = UUID(), candidates: [CacheCandidate], createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
        self.candidates = candidates.filter { $0.isSelected && $0.risk != .protected }
    }
}

public enum CleanupOperation: String, Codable, Sendable {
    case trash
    case permanent
}

public enum CleanupStatus: String, Codable, Sendable {
    case moved
    case removed
    case restored
    case missing
    case skipped
    case failed
}

public struct CleanupRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var originalURL: URL?
    public var trashURL: URL?
    public let operation: CleanupOperation
    public let estimatedBytes: Int64
    public var reclaimedBytes: Int64?
    public var status: CleanupStatus
    public let createdAt: Date
    public var detail: String?

    public init(
        id: UUID = UUID(),
        originalURL: URL?,
        trashURL: URL?,
        operation: CleanupOperation,
        estimatedBytes: Int64,
        reclaimedBytes: Int64? = nil,
        status: CleanupStatus,
        createdAt: Date = .now,
        detail: String? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.trashURL = trashURL
        self.operation = operation
        self.estimatedBytes = estimatedBytes
        self.reclaimedBytes = reclaimedBytes
        self.status = status
        self.createdAt = createdAt
        self.detail = detail
    }
}

public enum SafetyMode: Sendable {
    case readOnly
    case enabled
}

public enum VacuumCoreError: LocalizedError, Sendable {
    case readOnlyBeta
    case invalidCandidate(String)
    case processRunning(String)
    case recordNotRestorable
    case notVacuumTrash

    public var errorDescription: String? {
        switch self {
        case .readOnlyBeta:
            "Cleanup is disabled in this read-only beta."
        case let .invalidCandidate(reason):
            "Safety validation failed: \(reason)"
        case let .processRunning(name):
            "\(name) is running. Quit it before cleaning."
        case .recordNotRestorable:
            "This item is no longer available to restore."
        case .notVacuumTrash:
            "Vacuum can only purge items it moved to Trash."
        }
    }
}
