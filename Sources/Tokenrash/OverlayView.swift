import SwiftUI

struct OverlayView: View {
    @Environment(BudgetStore.self) private var store
    var onSignIn: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let budget = store.budget
        let remaining = budget?.remainingFraction ?? 0.62
        let plate = budget.map { TokenFormat.tokens($0.remaining) } ?? "—"
        let caption: String = {
            guard let budget else { return "daily budget" }
            let reset = budget.resetsAt ?? TokenFormat.nextMidnight()
            return "left · resets \(TokenFormat.countdown(to: reset))"
        }()

        VStack(spacing: 0) {
            HourglassView(
                remainingFraction: remaining,
                usedTokens: budget?.used ?? 0,
                limitTokens: budget?.limit ?? 1,
                caption: caption,
                plate: plate,
                isDemo: store.isDemo,
                reduceMotion: reduceMotion
            )
            .onTapGesture {
                if store.budget == nil { onSignIn() }
            }
        }
        .padding(8)
        .background(.clear)
    }
}
