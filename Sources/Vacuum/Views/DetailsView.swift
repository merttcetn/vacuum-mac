import SwiftUI
import VacuumCore

private enum DetailDestination: String, CaseIterable, Identifiable {
    case recommendations
    case overview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommendations: "Recommendations"
        case .overview: "Disk Overview"
        }
    }

    var symbol: String {
        switch self {
        case .recommendations: "checklist"
        case .overview: "chart.bar.xaxis"
        }
    }
}

struct DetailsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var destination: DetailDestination? = .recommendations
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(DetailDestination.allCases, selection: $destination) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            switch destination ?? .recommendations {
            case .recommendations:
                RecommendationsView(searchText: searchText)
            case .overview:
                DiskOverviewView()
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Path, rule, or reason"
        )
        .toolbar {
            ToolbarItemGroup {
                if model.phase == .scanning {
                    Button("Cancel", role: .cancel) {
                        model.cancelScan()
                    }
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        model.startScan()
                    } label: {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                }
                Button {
                    openWindow(id: "history")
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .alert("Read-only beta", isPresented: $model.showReadOnlyMessage) {
            Button("Continue Scanning", role: .cancel) {}
        } message: {
            Text("Cleanup is deliberately disabled while Vacuum's scanner is being dogfooded. Nothing has been moved or deleted.")
        }
        .alert("Vacuum could not complete that action", isPresented: errorPresented) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label("Read-only beta", systemImage: "eye.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text("No files are changed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }
}

private struct RecommendationsView: View {
    @EnvironmentObject private var model: AppModel
    let searchText: String

    var body: some View {
        VStack(spacing: 0) {
            if let progress = model.progress, model.phase == .scanning {
                scanProgress(progress)
            }

            if let snapshot = model.snapshot {
                candidateList(snapshot)
            } else {
                EmptyScanView(action: model.startScan)
            }

            selectionBar
        }
        .navigationTitle("Recommendations")
    }

    private func scanProgress(_ progress: ScanProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Scanning developer storage…")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(progress.completed) / \(progress.total)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fraction)
            Text(progress.currentPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.blue.opacity(0.07))
    }

    private func candidateList(_ snapshot: ScanSnapshot) -> some View {
        List {
            summary(snapshot)

            ForEach(RiskLevel.allCases, id: \.self) { risk in
                let candidates = filteredCandidates(snapshot, risk: risk)
                if !candidates.isEmpty {
                    Section {
                        ForEach(candidates) { candidate in
                            CandidateRow(candidate: candidate)
                        }
                    } header: {
                        riskHeader(risk, candidates: candidates)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func summary(_ snapshot: ScanSnapshot) -> some View {
        HStack(spacing: 0) {
            summaryMetric(
                title: "Safe",
                value: byteString(snapshot.total(for: .safe)),
                color: VacuumPalette.safe
            )
            Divider().frame(height: 38)
            summaryMetric(
                title: "Review",
                value: byteString(snapshot.total(for: .review)),
                color: VacuumPalette.review
            )
            Divider().frame(height: 38)
            summaryMetric(
                title: "Protected",
                value: byteString(snapshot.total(for: .protected)),
                color: VacuumPalette.protected
            )
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func riskHeader(_ risk: RiskLevel, candidates: [CacheCandidate]) -> some View {
        HStack {
            RiskBadge(risk: risk)
            Text(risk.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer()
            TerminalValue(value: byteString(candidates.reduce(0) { $0 + $1.allocatedSize }))
        }
        .padding(.top, 10)
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.selectedCount) item(s) selected")
                        .font(.subheadline.weight(.semibold))
                    Text("\(byteString(model.selectedBytes)) would be moved to Trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.requestCleanup()
                } label: {
                    Label("Cleanup unavailable in beta", systemImage: "eye.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(model.selectedCount == 0)
            }
            .padding(14)
            .background(.bar)
        }
    }

    private func filteredCandidates(_ snapshot: ScanSnapshot, risk: RiskLevel) -> [CacheCandidate] {
        snapshot.candidates.filter { candidate in
            guard candidate.risk == risk else { return false }
            guard !searchText.isEmpty else { return true }
            return [
                candidate.url.path,
                candidate.ruleID,
                candidate.reason,
                candidate.rebuildImpact
            ].contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
}

private struct CandidateRow: View {
    @EnvironmentObject private var model: AppModel
    let candidate: CacheCandidate
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: selectedBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(candidate.risk == .protected)
                .padding(.top, 3)
                .accessibilityLabel("Select \(candidate.url.lastPathComponent)")

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(candidate.url.lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    RiskBadge(risk: candidate.risk)
                    Spacer()
                    Text(byteString(candidate.allocatedSize))
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }

                Text(candidate.url.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    Label {
                        Text(candidate.lastModified, style: .relative)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    Text(candidate.ruleID)
                        .font(.system(.caption2, design: .monospaced))
                    Spacer()
                    Button(expanded ? "Less" : "Why?") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if expanded {
                    VStack(alignment: .leading, spacing: 7) {
                        explanation("Classification", text: candidate.reason, icon: candidate.risk.symbol)
                        explanation("After cleanup", text: candidate.rebuildImpact, icon: "arrow.triangle.2.circlepath")
                    }
                    .padding(10)
                    .background(candidate.risk.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, 7)
        .opacity(candidate.risk == .protected ? 0.78 : 1)
    }

    private var selectedBinding: Binding<Bool> {
        Binding(
            get: { model.isSelected(candidate) },
            set: { model.setSelected($0, candidate: candidate) }
        )
    }

    private func explanation(_ title: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(candidate.risk.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DiskOverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        volumeCard(snapshot)
                        ReadOnlyBanner()
                        riskExplanation
                    }
                    .padding(24)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyScanView(action: model.startScan)
            }
        }
        .navigationTitle("Disk Overview")
    }

    private func volumeCard(_ snapshot: ScanSnapshot) -> some View {
        let used = max(0, snapshot.volume.totalBytes - snapshot.volume.availableBytes)
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label(snapshot.volume.name, systemImage: "internaldrive.fill")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(byteString(snapshot.volume.availableBytes)) available")
                    .font(.system(.subheadline, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(used),
                total: Double(max(1, snapshot.volume.totalBytes))
            )
            .controlSize(.large)

            HStack {
                Text("\(byteString(used)) used")
                Spacer()
                Text("\(byteString(snapshot.volume.totalBytes)) total")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var riskExplanation: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("How Vacuum decides")
                .font(.title3.weight(.semibold))
            ForEach(RiskLevel.allCases, id: \.self) { risk in
                HStack(alignment: .top, spacing: 12) {
                    RiskBadge(risk: risk)
                    Text(risk.guidance)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Allocated sizes are APFS-aware estimates. Vacuum does not follow symbolic links, run package-manager commands, or download cleanup rules.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
        }
    }
}
