import SwiftUI
import VacuumCore

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ReadOnlyBanner(compact: true)
                .padding(14)

            Divider()

            if model.history.isEmpty {
                ContentUnavailableView(
                    "No Cleanup History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Only items moved by Vacuum appear here. Path details expire after 30 days.")
                )
            } else {
                List(model.history) { record in
                    HistoryRow(record: record)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Cleanup History")
        .task {
            await model.refreshHistory()
        }
        .alert("Vacuum could not complete that action", isPresented: errorPresented) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var model: AppModel
    let record: CleanupRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .font(.title3)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(displayName)
                        .font(.body.weight(.medium))
                    statusLabel
                    Spacer()
                    Text(byteString(record.estimatedBytes))
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                }

                if let path = record.originalURL?.path {
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack {
                    Text(record.createdAt, style: .relative)
                    Text("•")
                    Text(record.operation == .trash ? "Moved to Trash" : "Permanent")
                    if let detail = record.detail {
                        Text("•")
                        Text(detail)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if record.status == .moved {
                    HStack(spacing: 10) {
                        Button("Restore") {
                            Task { await model.restore(record) }
                        }
                        .disabled(AppModel.readOnlyBeta)

                        HoldToConfirmButton(
                            title: AppModel.readOnlyBeta ? "Purge unavailable in beta" : "Hold to Purge",
                            systemImage: "trash.slash",
                            disabled: AppModel.readOnlyBeta
                        ) {
                            Task { await model.purge(record) }
                        }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private var displayName: String {
        record.originalURL?.lastPathComponent
            ?? record.trashURL?.lastPathComponent
            ?? "Expired history item"
    }

    private var statusLabel: some View {
        Text(record.status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.10), in: Capsule())
    }

    private var statusSymbol: String {
        switch record.status {
        case .moved: "trash.fill"
        case .removed: "checkmark.circle.fill"
        case .restored: "arrow.uturn.backward.circle.fill"
        case .missing: "questionmark.folder.fill"
        case .skipped: "forward.fill"
        case .failed: "xmark.octagon.fill"
        @unknown default: "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .moved: .blue
        case .removed, .restored: VacuumPalette.safe
        case .missing, .skipped: VacuumPalette.review
        case .failed: VacuumPalette.protected
        @unknown default: .secondary
        }
    }
}
