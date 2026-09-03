import SwiftUI

struct SplitFlapBoard: View {
    let text: String
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                SplitFlapCell(
                    value: String(character),
                    delay: 0.05 * Double(index),
                    reduceMotion: reduceMotion
                )
            }
        }
    }
}

private struct SplitFlapCell: View {
    let value: String
    let delay: TimeInterval
    let reduceMotion: Bool

    private let tile = CGSize(width: 15, height: 28)
    private let fontSize: CGFloat = 16
    private let gap: CGFloat = 0.9

    @State private var shown = " "
    @State private var incoming = " "
    @State private var foldTop = false
    @State private var dropBottom = false
    @State private var flipTask: Task<Void, Never>?

    var body: some View {
        let halfHeight = (tile.height - gap) / 2
        ZStack {
            VStack(spacing: 0) {
                face(incoming, anchor: .top)
                    .frame(height: halfHeight, alignment: .top)
                    .clipped()
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(height: gap)
                face(dropBottom ? incoming : shown, anchor: .bottom)
                    .frame(height: halfHeight, alignment: .bottom)
                    .clipped()
            }

            VStack(spacing: 0) {
                face(shown, anchor: .top)
                    .frame(height: halfHeight, alignment: .top)
                    .clipped()
                    .rotation3DEffect(
                        .degrees(foldTop ? -90 : 0),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .bottom,
                        perspective: 0.55
                    )
                Rectangle().fill(.clear).frame(height: gap)
                face(incoming, anchor: .bottom)
                    .frame(height: halfHeight, alignment: .bottom)
                    .clipped()
                    .rotation3DEffect(
                        .degrees(dropBottom ? 0 : 90),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .top,
                        perspective: 0.55
                    )
                    .opacity(foldTop ? 1 : 0)
            }
        }
        .frame(width: tile.width, height: tile.height)
        .clipShape(RoundedRectangle(cornerRadius: 2.2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .stroke(Palette.brassDark.opacity(0.55), lineWidth: 0.6)
        )
        .onAppear {
            shown = value
            incoming = value
        }
        .onChange(of: value) { _, newValue in
            flipTask?.cancel()
            flipTask = Task { await flip(to: newValue) }
        }
    }

    private func face(_ glyph: String, anchor: Alignment) -> some View {
        Text(glyph)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.parchment)
            .frame(width: tile.width, height: tile.height, alignment: .center)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.14, blue: 0.10),
                        Color(red: 0.07, green: 0.05, blue: 0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: tile.height, alignment: anchor)
    }

    @MainActor
    private func flip(to newValue: String) async {
        if reduceMotion || newValue == shown {
            shown = newValue
            incoming = newValue
            foldTop = false
            dropBottom = false
            return
        }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }
        incoming = newValue
        foldTop = false
        dropBottom = false
        let variant = UInt64((delay * 1000).rounded()) &+ UInt64(newValue.unicodeScalars.first?.value ?? 0)
        FlapAudio.tick(variant: variant)
        withAnimation(.easeIn(duration: 0.13)) { foldTop = true }
        try? await Task.sleep(nanoseconds: 130_000_000)
        guard !Task.isCancelled else { return }
        FlapAudio.clack(variant: variant &+ 17)
        withAnimation(.easeOut(duration: 0.13)) { dropBottom = true }
        try? await Task.sleep(nanoseconds: 130_000_000)
        guard !Task.isCancelled else { return }
        shown = newValue
        foldTop = false
        dropBottom = false
    }
}
