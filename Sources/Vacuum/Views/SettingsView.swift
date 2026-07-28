import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(model)
                .environmentObject(updates)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            LocationSettingsView()
                .environmentObject(model)
                .tabItem {
                    Label("Locations", systemImage: "folder")
                }

            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .padding(16)
        .alert("Vacuum could not update that setting", isPresented: errorPresented) {
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

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open Vacuum at login", isOn: loginBinding)
                Text("Off by default. macOS may ask you to approve Vacuum in Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: $updates.automaticallyChecksForUpdates
                )
                HStack {
                    Text("Updates are the only network access Vacuum performs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now…") {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                }
            }

            Section("Safety mode") {
                LabeledContent("Current mode") {
                    Label("Read-only beta", systemImage: "eye.fill")
                        .foregroundStyle(.blue)
                }
                Text("Scanning and recommendations are available. Moving, restoring, purging, and permanent cleanup are disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { model.loginAtLaunch },
            set: { model.setLoginAtLaunch($0) }
        )
    }
}

private struct LocationSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Approved locations")
                    .font(.headline)
                Text("Project scanning only recognizes supported artifacts with a matching manifest or lockfile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List {
                Section("Built in") {
                    rootRow(
                        title: "Primary Codex profile",
                        path: model.primaryCodexProfile.path,
                        kind: .codexProfile
                    )
                }

                ForEach([RootKind.codexProfile, .project], id: \.self) { kind in
                    let matching = model.roots.filter { $0.kind == kind }
                    if !matching.isEmpty {
                        Section(kind == .codexProfile ? "Additional profiles" : "Project folders") {
                            ForEach(matching) { root in
                                HStack {
                                    rootRow(
                                        title: root.resolvedURL().lastPathComponent,
                                        path: root.path,
                                        kind: root.kind
                                    )
                                    Spacer()
                                    Button {
                                        model.removeRoot(root)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(root.path)")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Button("Add Codex Profile…") {
                    model.chooseFolder(kind: .codexProfile)
                }
                Button("Add Project Folder…") {
                    model.chooseFolder(kind: .project)
                }
                Spacer()
            }
        }
    }

    private func rootRow(title: String, path: String, kind: RootKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind == .project ? "folder.fill" : "terminal.fill")
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section("Data") {
                privacyRow("No telemetry", detail: "Vacuum does not collect analytics, identifiers, paths, or usage data.", icon: "waveform.slash")
                privacyRow("Local history", detail: "Cleanup history stays on this Mac. Path details are removed after 30 days.", icon: "clock")
                privacyRow("Embedded rules", detail: "Classification rules ship inside the app and are never downloaded remotely.", icon: "shippingbox.fill")
            }

            Section("Permissions") {
                privacyRow("Standard access first", detail: "Full Disk Access is only relevant when macOS denies a specific target. Vacuum has no admin helper.", icon: "lock.shield")
                privacyRow("No shell commands", detail: "Vacuum never invokes Mole, package managers, or cleanup subprocesses.", icon: "terminal")
            }
        }
        .formStyle(.grouped)
    }

    private func privacyRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
