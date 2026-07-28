import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updates: UpdateController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            status
            Divider()
            actions
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .task {
            showOnboarding = !model.onboardingComplete
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(model)
        }
        .alert("Vacuum", isPresented: errorPresented) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(0.07))
                Image(systemName: "internaldrive.fill")
                    .font(.title2)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                            .offset(x: 7, y: -7)
                    }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Vacuum")
                    .font(.headline)
                Text("Developer Storage Doctor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("BETA")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.10), in: Capsule())
        }
        .padding(16)
    }

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            diskRow

            if model.phase == .scanning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: model.progress?.fraction ?? 0)
                    HStack {
                        Text("Scanning")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(model.progress?.currentPath ?? "Preparing…")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 190, alignment: .trailing)
                    }
                }
            } else {
                HStack {
                    metric(title: "Safe", value: byteString(model.safeBytes), color: VacuumPalette.safe)
                    Divider().frame(height: 32)
                    metric(
                        title: "Last scan",
                        value: model.lastScannedAt.map(relativeScanDate) ?? "Never",
                        color: .secondary
                    )
                }
            }

            if model.snapshot == nil {
                Text("\(model.discoveredTargets.count) supported location(s) detected. Measurement starts only when you scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    private var diskRow: some View {
        let volume = model.snapshot?.volume
        let available = volume?.availableBytes ?? 0
        let total = volume?.totalBytes ?? 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(volume?.name ?? "Startup Disk", systemImage: "internaldrive")
                    .font(.subheadline.weight(.medium))
                Spacer()
                TerminalValue(
                    value: total > 0 ? "\(byteString(available)) free" : "Awaiting scan",
                    color: total > 0 && available < total / 10 ? VacuumPalette.review : .secondary
                )
            }
            if total > 0 {
                ProgressView(value: Double(total - available), total: Double(total))
                    .tint(available < total / 10 ? VacuumPalette.review : .blue)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack {
                if model.phase == .scanning {
                    Button("Cancel Scan", role: .cancel) {
                        model.cancelScan()
                    }
                } else {
                    Button {
                        model.startScan()
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Open Details") {
                    openWindow(id: "details")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(.defaultAction)

                Spacer()
            }

            HStack {
                Button {
                    openWindow(id: "history")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit Vacuum")
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relativeScanDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }
}
