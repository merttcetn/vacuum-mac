import SwiftUI
import VacuumCore

enum VacuumPalette {
    static let safe = Color(red: 0.18, green: 0.72, blue: 0.43)
    static let review = Color(red: 0.95, green: 0.62, blue: 0.16)
    static let protected = Color(red: 0.90, green: 0.28, blue: 0.30)
    static let terminal = Color(red: 0.10, green: 0.12, blue: 0.12)
}

extension RiskLevel {
    var color: Color {
        switch self {
        case .safe: VacuumPalette.safe
        case .review: VacuumPalette.review
        case .protected: VacuumPalette.protected
        @unknown default: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .review: "exclamationmark.triangle.fill"
        case .protected: "lock.fill"
        @unknown default: "questionmark.circle.fill"
        }
    }

    var guidance: String {
        switch self {
        case .safe: "Recreatable data with a low recovery cost"
        case .review: "Inspect the rebuild or download cost before selecting"
        case .protected: "Required, active, or uncertain data that Vacuum will not remove"
        @unknown default: "Unknown risk classification"
        }
    }
}

struct VacuumMenuBarIcon: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "sparkles")
                .font(.system(size: 7, weight: .bold))
                .offset(x: 4, y: -3)
        }
        .accessibilityLabel("Vacuum")
    }
}

struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Label(risk.rawValue, systemImage: risk.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(risk.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(risk.color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(risk.rawValue) risk")
    }
}

struct TerminalValue: View {
    let value: String
    var color: Color = .secondary

    var body: some View {
        Text(value)
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .foregroundStyle(color)
            .textSelection(.enabled)
    }
}

struct ReadOnlyBanner: View {
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Read-only beta")
                    .font(.subheadline.weight(.semibold))
                if !compact {
                    Text("Vacuum can scan and explain recommendations, but it will not move or delete files in this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(.blue.opacity(0.18))
        }
    }
}

struct EmptyScanView: View {
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Ready to inspect", systemImage: "internaldrive")
        } description: {
            Text("Run a manual scan to measure allocated disk space and classify developer storage.")
        } actions: {
            Button("Scan Now", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct HoldToConfirmButton: View {
    let title: String
    let systemImage: String
    var disabled = false
    let action: () -> Void

    @GestureState private var pressing = false
    @State private var showAccessibleConfirmation = false

    var body: some View {
        Label(pressing ? "Keep holding…" : title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(disabled ? Color.secondary : Color.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.red.opacity(disabled ? 0.04 : 0.10), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.red.opacity(disabled ? 0.08 : 0.22))
            }
            .contentShape(Rectangle())
            .opacity(pressing ? 0.65 : 1)
            .scaleEffect(pressing ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: pressing)
            .gesture(
                LongPressGesture(minimumDuration: 1.5)
                    .updating($pressing) { current, state, _ in
                        state = current
                    }
                    .onEnded { _ in
                        guard !disabled else { return }
                        action()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(disabled ? "Unavailable in the read-only beta." : "Press and hold for one and a half seconds.")
            .accessibilityAction(named: "Confirm permanent deletion") {
                guard !disabled else { return }
                showAccessibleConfirmation = true
            }
            .confirmationDialog(
                "Permanently remove this Vacuum item?",
                isPresented: $showAccessibleConfirmation,
                titleVisibility: .visible
            ) {
                Button("Permanently Remove", role: .destructive, action: action)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is the keyboard and VoiceOver equivalent of holding the control for 1.5 seconds.")
            }
    }
}

func byteString(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
