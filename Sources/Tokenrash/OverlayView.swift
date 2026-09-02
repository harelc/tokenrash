import SwiftUI
import AppKit

struct OverlayView: View {
    @Environment(BudgetStore.self) private var store
    var onSignIn: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let design = CGSize(width: 200, height: 300)

    var body: some View {
        let remaining = store.remainingFraction
        let plate = store.budget.map { TokenFormat.usd($0.remaining) } ?? "—"

        GeometryReader { geo in
            let scale = min(geo.size.width / design.width, geo.size.height / design.height)
            VStack(spacing: 0) {
                HourglassView(
                    remainingFraction: remaining,
                    reduceMotion: reduceMotion,
                    siren: store.isSiren
                )
                .frame(width: design.width, height: 248)

                board(plate: plate)
                    .frame(width: design.width, height: 52)
            }
            .frame(width: design.width, height: design.height)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if store.budget == nil { onSignIn() }
            }
        }
        .background(.clear)
    }

    private func board(plate: String) -> some View {
        SplitFlapBoard(text: plate, reduceMotion: reduceMotion)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.brassLite, Palette.brass, Palette.brassDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.horizontal, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.brassDark.opacity(0.38))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                    )
            )
    }
}
