import SwiftUI

struct LookChrome: View {
    var look: WidgetLook
    var remaining: String
    var spent: String
    var reduceMotion: Bool

    var showTop: Bool = true
    var showBottom: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if showTop {
                LookYoke(text: remaining, reduceMotion: reduceMotion, look: look, kind: .crown)
                    .frame(width: HourglassChrome.design.width * look.crownWidth, height: HourglassChrome.yoke)
            }
            Spacer(minLength: 0)
            if showBottom {
                LookYoke(text: spent, reduceMotion: reduceMotion, look: look, kind: .plinth)
                    .frame(width: HourglassChrome.design.width * look.plinthWidth, height: HourglassChrome.yoke)
            }
        }
    }
}

private struct LookYoke: View {
    enum Kind { case crown, plinth }

    var text: String
    var reduceMotion: Bool
    var look: WidgetLook
    var kind: Kind

    var body: some View {
        switch look {
        case .horologist:
            metalYoke(topRound: kind == .crown ? 15 : 4, botRound: kind == .crown ? 4 : 15) {
                SplitFlapBoard(text: text, reduceMotion: reduceMotion)
            }
        case .inkwell:
            inkwellYoke
        case .playroom:
            playroomYoke
        case .telemetry:
            telemetryYoke
        case .jelly:
            jellyYoke
        }
    }

    private func metalYoke<Content: View>(topRound: CGFloat, botRound: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: topRound,
                bottomLeadingRadius: botRound,
                bottomTrailingRadius: botRound,
                topTrailingRadius: topRound,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [look.metalLite, look.metal, look.metalDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: topRound,
                    bottomLeadingRadius: botRound,
                    bottomTrailingRadius: botRound,
                    topTrailingRadius: topRound,
                    style: .continuous
                )
                .stroke(look.metalDark.opacity(0.62), lineWidth: 0.8)
            )

            UnevenRoundedRectangle(
                topLeadingRadius: max(2.5, topRound - 7),
                bottomLeadingRadius: max(2.5, botRound - 7),
                bottomTrailingRadius: max(2.5, botRound - 7),
                topTrailingRadius: max(2.5, topRound - 7),
                style: .continuous
            )
            .fill(look.well)
            .padding(.horizontal, 7)
            .padding(.vertical, 8)

            content()
        }
        .overlay(alignment: kind == .crown ? .bottom : .top) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [look.metalLite, look.metal, look.metalDark],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(Capsule().stroke(look.metalDark.opacity(0.5), lineWidth: 0.5))
                .padding(.horizontal, 18)
                .frame(height: 11)
                .offset(y: kind == .crown ? 5 : -5)
        }
    }

    private var inkwellYoke: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(look.metal)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(look.numeral.opacity(0.55), lineWidth: 0.7)
                )
            Text(text)
                .font(.system(size: 17, weight: .medium, design: .serif))
                .monospacedDigit()
                .foregroundStyle(look.numeral)
                .tracking(1.4)
        }
    }

    private var playroomYoke: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [look.metalLite, look.metal, look.metalDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Capsule()
                .fill(look.well)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            Text(text)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(look.numeral)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
        }
    }

    private var telemetryYoke: some View {
        ZStack {
            Rectangle()
                .stroke(look.numeral.opacity(0.55), lineWidth: 1)
                .background(look.well.opacity(0.88))
            HStack(spacing: 0) {
                Rectangle()
                    .fill(look.numeral)
                    .frame(width: 3)
                Text(text)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(look.numeral)
                    .tracking(1.2)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var jellyYoke: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), look.metalLite, look.metal],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.2)
                )
            Text(text)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(look.numeral)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 12)
        }
    }
}
