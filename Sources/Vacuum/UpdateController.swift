import Combine
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    let controller: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != controller.updater.automaticallyChecksForUpdates else {
                return
            }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private var canCheckObservation: NSKeyValueObservation?
    private var automaticChecksObservation: NSKeyValueObservation?

    override init() {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller = updaterController
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        super.init()

        canCheckObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
        automaticChecksObservation = updaterController.updater.observe(
            \.automaticallyChecksForUpdates,
            options: [.new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
