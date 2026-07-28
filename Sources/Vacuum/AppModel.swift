import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications
import VacuumCore

enum ScanPhase: Equatable {
    case idle
    case discovering
    case scanning

    var isBusy: Bool {
        self != .idle
    }
}

enum RootKind: String, Codable, Sendable {
    case codexProfile
    case project

    var title: String {
        switch self {
        case .codexProfile: "Codex profile"
        case .project: "Project folder"
        }
    }
}

struct StoredRoot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: RootKind
    let path: String
    let bookmark: Data?

    init(id: UUID = UUID(), kind: RootKind, url: URL, bookmark: Data?) {
        self.id = id
        self.kind = kind
        self.path = url.standardizedFileURL.path
        self.bookmark = bookmark
    }

    func resolvedURL() -> URL {
        guard let bookmark else { return URL(filePath: path, directoryHint: .isDirectory) }
        var stale = false
        return (try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )) ?? URL(filePath: path, directoryHint: .isDirectory)
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let readOnlyBeta = true

    @Published private(set) var snapshot: ScanSnapshot?
    @Published private(set) var progress: ScanProgress?
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var discoveredTargets: [URL] = []
    @Published private(set) var selectedCandidateIDs: Set<UUID> = []
    @Published private(set) var roots: [StoredRoot] = []
    @Published private(set) var history: [CleanupRecord] = []
    @Published private(set) var loginAtLaunch = false
    @Published var lastError: String?
    @Published var showReadOnlyMessage = false
    @Published var onboardingCodexMastersoft = false
    @Published var onboardingDeveloperFolder = false

    @Published var onboardingComplete: Bool {
        didSet {
            defaults.set(onboardingComplete, forKey: Keys.onboardingComplete)
        }
    }

    let homeDirectory: URL
    let primaryCodexProfile: URL
    let suggestedCodexProfile: URL
    let suggestedProjectRoot: URL

    private let defaults: UserDefaults
    private let scanner: ScanCoordinator
    private let historyStore: CleanupHistoryStore
    private let cleanup: CleanupCoordinator
    private var scanTask: Task<Void, Never>?

    private enum Keys {
        static let roots = "vacuum.approvedRoots.v1"
        static let onboardingComplete = "vacuum.onboardingComplete"
    }

    init(
        defaults: UserDefaults = .standard,
        scanner: ScanCoordinator = ScanCoordinator()
    ) {
        self.defaults = defaults
        self.scanner = scanner
        homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        primaryCodexProfile = homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
        suggestedCodexProfile = homeDirectory.appending(path: ".codex-mastersoft", directoryHint: .isDirectory)
        suggestedProjectRoot = homeDirectory.appending(path: "Developer", directoryHint: .isDirectory)

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appending(path: "Vacuum", directoryHint: .isDirectory)
            ?? homeDirectory.appending(path: "Library/Application Support/Vacuum", directoryHint: .isDirectory)
        let store = CleanupHistoryStore(fileURL: support.appending(path: "cleanup-history.json"))
        historyStore = store
        cleanup = CleanupCoordinator(mode: .readOnly, historyStore: store)

        if let data = defaults.data(forKey: Keys.roots),
           let decoded = try? JSONDecoder().decode([StoredRoot].self, from: data) {
            roots = decoded
        }
        onboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
            || ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
        loginAtLaunch = SMAppService.mainApp.status == .enabled

        Task { [weak self] in
            await self?.refreshHistory()
            await self?.quickDiscover()
        }
    }

    deinit {
        scanTask?.cancel()
    }

    var configuration: ScanConfiguration {
        var codex = roots
            .filter { $0.kind == .codexProfile }
            .map { $0.resolvedURL() }
        if FileManager.default.fileExists(atPath: primaryCodexProfile.path) {
            codex.append(primaryCodexProfile)
        }
        let projects = roots
            .filter { $0.kind == .project }
            .map { $0.resolvedURL() }
        return ScanConfiguration(
            homeDirectory: homeDirectory,
            codexProfiles: uniqueURLs(codex),
            projectRoots: uniqueURLs(projects)
        )
    }

    var safeBytes: Int64 {
        snapshot?.total(for: .safe) ?? 0
    }

    var selectedBytes: Int64 {
        snapshot?.candidates.lazy
            .filter { self.selectedCandidateIDs.contains($0.id) }
            .reduce(0) { $0 + $1.allocatedSize } ?? 0
    }

    var selectedCount: Int {
        selectedCandidateIDs.count
    }

    var lastScannedAt: Date? {
        snapshot?.scannedAt
    }

    func quickDiscover() async {
        guard phase == .idle else { return }
        phase = .discovering
        discoveredTargets = await scanner.quickDiscovery(configuration: configuration)
        phase = .idle
    }

    func startScan() {
        guard scanTask == nil else { return }
        progress = ScanProgress(completed: 0, total: 0, currentPath: "Preparing…")
        phase = .scanning
        lastError = nil

        let configuration = configuration
        let scopedURLs = roots.map { $0.resolvedURL() }
        scanTask = Task { [weak self, scanner] in
            let accessed = scopedURLs.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                accessed.forEach { $0.stopAccessingSecurityScopedResource() }
            }

            do {
                let result = try await scanner.scan(configuration: configuration) { scanProgress in
                    await MainActor.run {
                        self?.progress = scanProgress
                    }
                }
                guard !Task.isCancelled else { return }
                self?.snapshot = result
                self?.selectedCandidateIDs = Set(
                    result.candidates
                        .filter { $0.risk == .safe && $0.isSelected }
                        .map(\.id)
                )
            } catch is CancellationError {
                // Cancellation is an expected user action.
            } catch {
                self?.lastError = error.localizedDescription
            }
            self?.progress = nil
            self?.phase = .idle
            self?.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func setSelected(_ selected: Bool, candidate: CacheCandidate) {
        guard candidate.risk != .protected else { return }
        if selected {
            selectedCandidateIDs.insert(candidate.id)
        } else {
            selectedCandidateIDs.remove(candidate.id)
        }
    }

    func isSelected(_ candidate: CacheCandidate) -> Bool {
        selectedCandidateIDs.contains(candidate.id)
    }

    func requestCleanup() {
        showReadOnlyMessage = true
    }

    func performCleanup(operation: CleanupOperation) async {
        guard let snapshot else { return }
        let candidates = snapshot.candidates.map { candidate -> CacheCandidate in
            var selected = candidate
            selected.isSelected = selectedCandidateIDs.contains(candidate.id)
            return selected
        }
        let records = await cleanup.execute(
            plan: CleanupPlan(candidates: candidates),
            operation: operation,
            allowedRoots: allowedRoots
        )
        await refreshHistory()

        let completed = records.filter { $0.status == .moved || $0.status == .removed }
        if !completed.isEmpty {
            await notifyCleanupCompleted(records: completed)
        } else if let detail = records.first?.detail {
            lastError = detail
        }
    }

    func restore(_ record: CleanupRecord) async {
        do {
            _ = try await cleanup.restore(recordID: record.id)
            await refreshHistory()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purge(_ record: CleanupRecord) async {
        do {
            _ = try await cleanup.purge(
                recordID: record.id,
                confirmationHeldFor: .milliseconds(1_500)
            )
            await refreshHistory()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshHistory() async {
        await cleanup.reconcileTrash()
        history = await historyStore.records()
    }

    func completeOnboarding() {
        if onboardingCodexMastersoft,
           FileManager.default.fileExists(atPath: suggestedCodexProfile.path) {
            addKnownRoot(suggestedCodexProfile, kind: .codexProfile)
        }
        if onboardingDeveloperFolder,
           FileManager.default.fileExists(atPath: suggestedProjectRoot.path) {
            addKnownRoot(suggestedProjectRoot, kind: .project)
        }
        onboardingComplete = true
        Task { await quickDiscover() }
    }

    func chooseFolder(kind: RootKind) {
        let panel = NSOpenPanel()
        panel.title = "Add \(kind.title)"
        panel.message = kind == .project
            ? "Vacuum will only inspect supported project artifacts inside this folder."
            : "Choose a Codex profile folder. Credentials and session data remain protected."
        panel.prompt = "Add Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.directoryURL = kind == .project ? suggestedProjectRoot : homeDirectory

        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { addKnownRoot($0, kind: kind) }
        Task { await quickDiscover() }
    }

    func removeRoot(_ root: StoredRoot) {
        roots.removeAll { $0.id == root.id }
        persistRoots()
        Task { await quickDiscover() }
    }

    func setLoginAtLaunch(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginAtLaunch = SMAppService.mainApp.status == .enabled
        } catch {
            loginAtLaunch = SMAppService.mainApp.status == .enabled
            lastError = error.localizedDescription
        }
    }

    private var allowedRoots: [URL] {
        let configured = configuration
        return uniqueURLs([homeDirectory] + configured.codexProfiles + configured.projectRoots)
    }

    private func addKnownRoot(_ url: URL, kind: RootKind) {
        let standardized = url.standardizedFileURL
        guard !roots.contains(where: { $0.kind == kind && $0.path == standardized.path }) else {
            return
        }
        let bookmark = try? standardized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        roots.append(StoredRoot(kind: kind, url: standardized, bookmark: bookmark))
        persistRoots()
    }

    private func persistRoots() {
        guard let data = try? JSONEncoder().encode(roots) else { return }
        defaults.set(data, forKey: Keys.roots)
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var paths = Set<String>()
        return urls.filter { paths.insert($0.standardizedFileURL.path).inserted }
    }

    private func notifyCleanupCompleted(records: [CleanupRecord]) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else { return }

        let bytes = records.reduce(0) { $0 + $1.estimatedBytes }
        let content = UNMutableNotificationContent()
        content.title = "Vacuum cleanup complete"
        content.body = "\(records.count) item(s), \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) moved or removed."
        try? await center.add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }
}
