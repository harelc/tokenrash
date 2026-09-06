import SwiftUI
import AppKit

struct OverlayView: View {
    @Environment(BudgetStore.self) private var store
    var onSignIn: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let design = HourglassChrome.design

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / design.width, geo.size.height / design.height)
            ZStack {
                HourglassView(
                    remainingFraction: store.remainingFraction,
                    reduceMotion: reduceMotion,
                    siren: store.isSiren,
                    chrome: .instrument
                )
                .frame(width: design.width, height: design.height)

                VStack(spacing: 0) {
                    FlapYoke(text: remainingPlate, reduceMotion: reduceMotion, kind: .crown)
                        .frame(width: design.width * 0.88, height: HourglassChrome.yoke)
                    Spacer(minLength: 0)
                    FlapYoke(text: spentPlate, reduceMotion: reduceMotion, kind: .plinth)
                        .frame(width: design.width * 0.94, height: HourglassChrome.yoke)
                }
                .frame(width: design.width, height: design.height)
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

    private var remainingPlate: String {
        if let preview = store.previewRemainingPlate { return preview }
        if let fraction = store.previewRemaining, let budget = store.budget {
            return TokenFormat.usd(budget.limit * fraction)
        }
        return store.budget.map { TokenFormat.usd($0.remaining) } ?? "—"
    }

    private var spentPlate: String {
        if let preview = store.previewSpentPlate { return preview }
        if let fraction = store.previewRemaining, let budget = store.budget {
            return TokenFormat.usd(budget.limit * (1 - fraction))
        }
        return store.budget.map { TokenFormat.usd($0.used) } ?? "—"
    }
}

/// Brass crown or plinth — the metal the glass is set into, with the flap well inside.
private struct FlapYoke: View {
    enum Kind { case crown, plinth }

    var text: String
    var reduceMotion: Bool
    var kind: Kind

    var body: some View {
        let topR: CGFloat = kind == .crown ? 15 : 4
        let botR: CGFloat = kind == .crown ? 4 : 15
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: topR,
                bottomLeadingRadius: botR,
                bottomTrailingRadius: botR,
                topTrailingRadius: topR,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [Palette.brassLite, Palette.brass, Palette.brassDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: topR,
                    bottomLeadingRadius: botR,
                    bottomTrailingRadius: botR,
                    topTrailingRadius: topR,
                    style: .continuous
                )
                .stroke(Palette.brassDark.opacity(0.62), lineWidth: 0.8)
            )

            UnevenRoundedRectangle(
                topLeadingRadius: max(2.5, topR - 7),
                bottomLeadingRadius: max(2.5, botR - 7),
                bottomTrailingRadius: max(2.5, botR - 7),
                topTrailingRadius: max(2.5, topR - 7),
                style: .continuous
            )
            .fill(Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.92))
            .padding(.horizontal, 7)
            .padding(.vertical, 8)

            SplitFlapBoard(text: text, reduceMotion: reduceMotion)
        }
        .overlay(alignment: kind == .crown ? .bottom : .top) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Palette.brassLite, Palette.brass, Palette.brassDark],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(Capsule().stroke(Palette.brassDark.opacity(0.5), lineWidth: 0.5))
                .padding(.horizontal, 18)
                .frame(height: 11)
                .offset(y: kind == .crown ? 5 : -5)
        }
    }
}
