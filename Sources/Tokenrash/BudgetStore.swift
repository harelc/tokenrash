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

    var remainingFraction: Double {
        budget?.remainingFraction ?? 0.62
    }

    var isDemo: Bool { budget == nil }

    func apply(budget: TokenBudget, rawJSON: String) {
        self.budget = budget
        self.rawJSON = rawJSON
        self.lastFetch = Date()
        if let email = budget.email { self.email = email }
        phase = .live
    }

    func markSignedOut(_ message: String? = nil) {
        budget = nil
        if let message {
            phase = .error(message)
        } else {
            phase = .signedOut
        }
    }
}
