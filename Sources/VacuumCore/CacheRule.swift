import Foundation

public enum RuleDiscovery: Hashable, Sendable {
    case exact
    case children
    case codexProfile
    case playwright
    case projectArtifacts
}
public struct CacheRule: Identifiable, Hashable, Sendable {
    public let id: String
    public let root: URL
    public let discovery: RuleDiscovery
    public let defaultRisk: RiskLevel
    public let reason: String
    public let rebuildImpact: String
    public let minimumAge: TimeInterval?
    public let processGuard: Set<String>

    public init(
        id: String,
        root: URL,
        discovery: RuleDiscovery = .exact,
        defaultRisk: RiskLevel,
        reason: String,
        rebuildImpact: String,
        minimumAge: TimeInterval? = nil,
        processGuard: Set<String> = []
    ) {
        self.id = id
        self.root = root
        self.discovery = discovery
        self.defaultRisk = defaultRisk
        self.reason = reason
        self.rebuildImpact = rebuildImpact
        self.minimumAge = minimumAge
        self.processGuard = processGuard
    }
}

public enum RuleCatalog {
    private static let week: TimeInterval = 7 * 24 * 60 * 60

    public static func builtIn(configuration: ScanConfiguration) -> [CacheRule] {
        let home = configuration.homeDirectory
        func path(_ value: String) -> URL {
            home.appending(path: value, directoryHint: .isDirectory)
        }

        var rules = configuration.codexProfiles.map {
            CacheRule(
                id: "codex.profile",
                root: $0,
                discovery: .codexProfile,
                defaultRisk: .review,
                reason: "Old, verified Codex cache data",
                rebuildImpact: "Codex may need to download runtime data again.",
                minimumAge: week,
                processGuard: ["Codex", "codex", "ChatGPT"]
            )
        }

        rules += [
            CacheRule(id: "claude.cache", root: path("Library/Caches/Claude"), defaultRisk: .safe, reason: "Recreatable Claude browser cache", rebuildImpact: "The next launch may be slower.", processGuard: ["Claude"]),
            CacheRule(id: "cursor.cache", root: path("Library/Caches/com.todesktop.230313mzl4w4u92"), defaultRisk: .safe, reason: "Recreatable Cursor browser cache", rebuildImpact: "Cursor will rebuild this cache.", processGuard: ["Cursor"]),
            CacheRule(id: "gemini.cache", root: path(".gemini/tmp"), defaultRisk: .safe, reason: "Gemini temporary cache", rebuildImpact: "Temporary data will be recreated.", processGuard: ["gemini"]),
            CacheRule(id: "opencode.cache", root: path(".cache/opencode"), defaultRisk: .review, reason: "Downloadable OpenCode package metadata", rebuildImpact: "Packages and model metadata may be downloaded again.", processGuard: ["opencode"]),
            CacheRule(id: "npm.cache", root: path(".npm/_cacache"), defaultRisk: .safe, reason: "Verified npm content-addressed cache", rebuildImpact: "npm will re-download packages.", processGuard: ["npm", "node"]),
            CacheRule(id: "npm.npx", root: path(".npm/_npx"), defaultRisk: .review, reason: "npx-installed tool environments", rebuildImpact: "npx tools will be installed again.", processGuard: ["npm", "npx", "node"]),
            CacheRule(id: "node-gyp.cache", root: path("Library/Caches/node-gyp"), defaultRisk: .safe, reason: "Downloaded Node.js build headers", rebuildImpact: "node-gyp will download headers again.", processGuard: ["node", "node-gyp"]),
            CacheRule(id: "uv.cache", root: path(".cache/uv"), defaultRisk: .safe, reason: "Verified uv package cache", rebuildImpact: "uv will re-download Python packages.", processGuard: ["uv"]),
            CacheRule(id: "homebrew.cache", root: path("Library/Caches/Homebrew"), defaultRisk: .safe, reason: "Homebrew download cache", rebuildImpact: "Homebrew will re-download bottles and sources.", processGuard: ["brew"]),
            CacheRule(id: "mole.cache", root: path(".cache/mole"), defaultRisk: .safe, reason: "Mole cache data", rebuildImpact: "Mole will rebuild its cache.", processGuard: ["mole"]),
            CacheRule(id: "xcode.deriveddata", root: path("Library/Developer/Xcode/DerivedData"), discovery: .children, defaultRisk: .safe, reason: "Derived Xcode build products", rebuildImpact: "Xcode will rebuild and re-index this project.", minimumAge: week, processGuard: ["Xcode", "xcodebuild", "swift-build"]),
            CacheRule(id: "playwright.js", root: path("Library/Caches/ms-playwright"), discovery: .playwright, defaultRisk: .review, reason: "Unreferenced Playwright browser revision", rebuildImpact: "Playwright will download this browser revision again.", processGuard: ["node", "playwright"]),
            CacheRule(id: "playwright.go", root: path("Library/Caches/ms-playwright-go"), discovery: .playwright, defaultRisk: .review, reason: "Unreferenced Playwright Go browser revision", rebuildImpact: "Playwright Go will download this browser revision again.", processGuard: ["go", "playwright"]),
            CacheRule(id: "dotslash.cache", root: path("Library/Caches/dotslash"), defaultRisk: .review, reason: "Downloaded dotslash artifacts", rebuildImpact: "Artifacts will be downloaded again.", processGuard: ["dotslash"]),
            CacheRule(id: "models.huggingface", root: path(".cache/huggingface/hub"), discovery: .children, defaultRisk: .review, reason: "Local Hugging Face model", rebuildImpact: "This model may require a large download."),
            CacheRule(id: "models.whisper", root: path(".cache/whisper"), discovery: .children, defaultRisk: .review, reason: "Local Whisper model", rebuildImpact: "This model will need to be downloaded again."),
            CacheRule(id: "models.ollama", root: path(".ollama/models"), discovery: .children, defaultRisk: .review, reason: "Local Ollama model data", rebuildImpact: "Ollama will need to pull this model again.", processGuard: ["ollama"]),
            CacheRule(id: "models.lmstudio", root: path(".cache/lm-studio/models"), discovery: .children, defaultRisk: .review, reason: "Local LM Studio model", rebuildImpact: "This model may require a large download.", processGuard: ["LM Studio"])
        ]

        rules += configuration.projectRoots.map {
            CacheRule(
                id: "projects.artifacts",
                root: $0,
                discovery: .projectArtifacts,
                defaultRisk: .review,
                reason: "Reproducible project dependency or build artifact",
                rebuildImpact: "The project must restore dependencies or rebuild."
            )
        }
        return rules
    }
}
