import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    privacyStrip
                    locations
                    ReadOnlyBanner()
                }
                .padding(28)
            }

            Divider()
            HStack {
                Text("You can change approved folders in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Get Started") {
                    model.completeOnboarding()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
        }
        .frame(width: 610, height: 610)
        .interactiveDismissDisabled()
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.blue.gradient)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .offset(x: 10, y: -9)
                    }
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text("Meet Vacuum")
                    .font(.largeTitle.bold())
                Text("A developer storage doctor that explains what is safe to recreate, what needs review, and what must stay protected.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyStrip: some View {
        HStack(spacing: 18) {
            privacyItem("Local only", icon: "macbook")
            privacyItem("Zero telemetry", icon: "waveform.slash")
            privacyItem("No automatic cleanup", icon: "hand.raised.fill")
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approve locations")
                .font(.title3.weight(.semibold))
            Text("Vacuum discovered the standard Codex profile. Optional locations stay off until you approve them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            locationRow(
                title: "Primary Codex profile",
                path: model.primaryCodexProfile.path,
                icon: "terminal.fill",
                state: .detected
            )

            if FileManager.default.fileExists(atPath: model.suggestedCodexProfile.path) {
                locationRow(
                    title: "Additional Codex profile",
                    path: model.suggestedCodexProfile.path,
                    icon: "person.crop.circle.badge.plus",
                    state: .toggle($model.onboardingCodexMastersoft)
                )
            }

            if FileManager.default.fileExists(atPath: model.suggestedProjectRoot.path) {
                locationRow(
                    title: "Developer projects",
                    path: model.suggestedProjectRoot.path,
                    icon: "folder.fill",
                    state: .toggle($model.onboardingDeveloperFolder)
                )
            }

            HStack {
                Button("Add Codex Profile…") {
                    model.chooseFolder(kind: .codexProfile)
                }
                Button("Add Project Folder…") {
                    model.chooseFolder(kind: .project)
                }
            }
        }
    }

    private enum LocationState {
        case detected
        case toggle(Binding<Bool>)
    }

    private func locationRow(
        title: String,
        path: String,
        icon: String,
        state: LocationState
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                TerminalValue(value: path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            switch state {
            case .detected:
                Label("Detected", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VacuumPalette.safe)
            case let .toggle(binding):
                Toggle("Approve", isOn: binding)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Approve \(title)")
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.primary.opacity(0.10))
        }
    }

    private func privacyItem(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
    }
}
