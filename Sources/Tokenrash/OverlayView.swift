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
            let look = store.look
            ZStack {
                HourglassView(
                    remainingFraction: store.remainingFraction,
                    usedFraction: store.usedFraction,
                    reduceMotion: reduceMotion,
                    siren: store.isSiren,
                    chrome: .instrument,
                    look: look,
                    animate: store.overlayActive && (store.budget != nil || store.previewRemaining != nil)
                )
                .frame(width: design.width, height: design.height)

                LookChrome(
                    look: look,
                    remaining: store.remainingPlate,
                    spent: store.spentPlate,
                    reduceMotion: reduceMotion,
                    showTop: store.showTopCounter,
                    showBottom: store.showBottomCounter
                )
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
}
