import Foundation
import Observation

@MainActor
@Observable
final class BudgetStore {
    enum Phase: Equatable {
        case signedOut
        case signingIn
        case live
        case error(String)
    }

    var phase: Phase = .signedOut
    var budget: TokenBudget?
    var rawJSON: String?
    var lastFetch: Date?
    var email: String?
    let alarms = BudgetAlarms()
    /// When set, the hourglass shows this remaining fraction so warnings can be previewed.
    var previewRemaining: Double?
    private var previewTask: Task<Void, Never>?

    var remainingFraction: Double {
        previewRemaining ?? budget?.remainingFraction ?? 0.62
    }

    var isSiren: Bool {
        remainingFraction <= 0.01 && (previewRemaining != nil || budget != nil)
    }

    var isDemo: Bool { budget == nil }

    func apply(budget: TokenBudget, rawJSON: String) {
        self.budget = budget
        self.rawJSON = rawJSON
        self.lastFetch = Date()
        if let email = budget.email { self.email = email }
        phase = .live
        alarms.observe(remaining: budget.remainingFraction)
    }

    func markSignedOut(_ message: String? = nil) {
        budget = nil
        if let message {
            phase = .error(message)
        } else {
            phase = .signedOut
        }
    }

    func previewWarning(_ step: TokenrashConfig.AlarmStep) {
        overlayPreview(remaining: step.remaining, sound: step.sound, hold: step.sound == .siren ? 4.0 : 1.8)
    }

    func previewAllWarnings() {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            for (index, step) in TokenrashConfig.alarmSteps.enumerated() {
                guard !Task.isCancelled else { return }
                previewRemaining = step.remaining
                AlarmAudio.play(step.sound)
                let hold: TimeInterval = step.sound == .siren ? 4.0 : (index == 0 ? 1.5 : 1.8)
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            previewRemaining = nil
        }
    }

    private func overlayPreview(remaining: Double, sound: TokenrashConfig.AlarmSound, hold: TimeInterval) {
        previewTask?.cancel()
        previewRemaining = remaining
        AlarmAudio.play(sound)
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            previewRemaining = nil
        }
    }
}
