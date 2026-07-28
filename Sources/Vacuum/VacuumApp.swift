import AppKit
import SwiftUI

@main
struct VacuumApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(updates)
        } label: {
            VacuumMenuBarIcon()
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Vacuum", id: "details") {
            DetailsView()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 580)
        }
        .defaultSize(width: 980, height: 700)
        .windowResizability(.contentMinSize)

        WindowGroup("Cleanup History", id: "history") {
            HistoryView()
                .environmentObject(model)
                .frame(minWidth: 660, minHeight: 440)
        }
        .defaultSize(width: 760, height: 540)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(updates)
                .frame(width: 560, height: 430)
        }

        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }
        }
    }
}
