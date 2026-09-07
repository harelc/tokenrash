import SwiftUI

/// Five distinct instruments — not tints of one hourglass.
enum WidgetLook: String, CaseIterable, Identifiable {
    case horologist
    case inkwell
    case playroom
    case telemetry
    case jelly

    var id: String { rawValue }

    private static let key = "widget.look"

    static var stored: WidgetLook {
        get { WidgetLook(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .horologist }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var menuTitle: String {
        switch self {
        case .horologist: "Horologist"
        case .inkwell: "Inkwell"
        case .playroom: "Playroom"
        case .telemetry: "Telemetry"
        case .jelly: "Jelly"
        }
    }

    var metalIndex: Float {
        switch self {
        case .horologist: 0
        case .inkwell: 1
        case .playroom: 2
        case .telemetry: 3
        case .jelly: 4
        }
    }

    var silhouette: GlassSilhouette {
        switch self {
        case .horologist: .classic
        case .inkwell: .column
        case .playroom: .toy
        case .telemetry: .diamond
        case .jelly: .blob
        }
    }

    var neck: CGFloat {
        switch self {
        case .horologist: 0.028
        case .inkwell: 0.018
        case .playroom: 0.075
        case .telemetry: 0.012
        case .jelly: 0.08
        }
    }

    var bulb: CGFloat {
        switch self {
        case .horologist: 0.48
        case .inkwell: 0.34
        case .playroom: 0.50
        case .telemetry: 0.46
        case .jelly: 0.52
        }
    }

    var wobble: CGFloat {
        switch self {
        case .horologist: 1.0
        case .inkwell: 0.25
        case .playroom: 1.6
        case .telemetry: 0.15
        case .jelly: 2.2
        }
    }

    var showTicks: Bool {
        switch self {
        case .horologist, .inkwell, .telemetry: true
        case .playroom, .jelly: false
        }
    }

    var streamWidth: CGFloat {
        switch self {
        case .horologist: 3.6
        case .inkwell: 2.2
        case .playroom: 5.4
        case .telemetry: 2.0
        case .jelly: 6.4
        }
    }

    var rimWidth: CGFloat {
        switch self {
        case .horologist: 1.6
        case .inkwell: 1.1
        case .playroom: 3.2
        case .telemetry: 1.2
        case .jelly: 2.6
        }
    }

    var crownWidth: CGFloat {
        switch self {
        case .horologist: 0.88
        case .inkwell: 0.70
        case .playroom: 0.92
        case .telemetry: 0.64
        case .jelly: 0.84
        }
    }

    var plinthWidth: CGFloat {
        switch self {
        case .horologist: 0.94
        case .inkwell: 0.70
        case .playroom: 0.92
        case .telemetry: 0.64
        case .jelly: 0.90
        }
    }

    var dockBackdrop: Color {
        switch self {
        case .horologist: Palette.soot
        case .inkwell: Color(red: 0.07, green: 0.06, blue: 0.05)
        case .playroom: Color(red: 0.93, green: 0.86, blue: 0.70)
        case .telemetry: Color(red: 0.05, green: 0.05, blue: 0.05)
        case .jelly: Color(red: 0.98, green: 0.93, blue: 0.90)
        }
    }

    func cavityFill(siren: Bool, pulse: Double) -> Color {
        if siren { return Color.red.opacity(0.12 + 0.38 * pulse) }
        switch self {
        case .horologist: return Palette.soot.opacity(0.55)
        case .inkwell: return Color(red: 0.05, green: 0.04, blue: 0.03).opacity(0.82)
        case .playroom: return Color(red: 0.98, green: 0.94, blue: 0.84).opacity(0.42)
        case .telemetry: return Color(red: 0.02, green: 0.02, blue: 0.02).opacity(0.78)
        case .jelly: return Color.white.opacity(0.22)
        }
    }

    func sand(remaining: Double, siren: Bool, pulse: Double) -> Color {
        if siren { return Color(red: 0.95, green: 0.08 + 0.18 * (1 - pulse), blue: 0.06) }
        let t = min(1, max(0, remaining))
        switch self {
        case .horologist:
            return Palette.sand(remaining: remaining)
        case .inkwell:
            if t >= 0.35 {
                return Color(red: 0.72, green: 0.16, blue: 0.12)
            }
            return Color(red: 0.78, green: 0.58, blue: 0.22)
        case .playroom:
            if t >= 0.4 {
                return Color(red: 0.86, green: 0.32, blue: 0.22)
            }
            return Color(red: 0.92, green: 0.62, blue: 0.18)
        case .telemetry:
            if t >= 0.22 {
                return Color(red: 0.96, green: 0.62, blue: 0.18)
            }
            return Color(red: 0.92, green: 0.28, blue: 0.12)
        case .jelly:
            if t >= 0.5 {
                return Color(red: 0.98, green: 0.78, blue: 0.72)
            }
            if t >= 0.22 {
                return Color(red: 0.92, green: 0.58, blue: 0.70)
            }
            return Color(red: 0.78, green: 0.42, blue: 0.62)
        }
    }

    func rimColors(siren: Bool, pulse: Double) -> [Color] {
        if siren {
            return [
                Color.red.opacity(0.35 + 0.55 * pulse),
                Color(red: 1, green: 0.2, blue: 0.1).opacity(0.8),
                Color.red.opacity(0.2 + 0.5 * pulse)
            ]
        }
        switch self {
        case .horologist:
            return [Color.white.opacity(0.55), Palette.brassLite.opacity(0.35), Color.white.opacity(0.12)]
        case .inkwell:
            return [Color(red: 0.82, green: 0.66, blue: 0.32).opacity(0.85), Color(red: 0.45, green: 0.32, blue: 0.12).opacity(0.5)]
        case .playroom:
            return [Color(red: 0.62, green: 0.40, blue: 0.18), Color(red: 0.42, green: 0.24, blue: 0.10)]
        case .telemetry:
            return [Color(red: 0.96, green: 0.70, blue: 0.28).opacity(0.9), Color(red: 0.55, green: 0.32, blue: 0.08).opacity(0.5)]
        case .jelly:
            return [Color.white.opacity(0.85), Color(red: 0.98, green: 0.72, blue: 0.78).opacity(0.45)]
        }
    }

    var highlight: Color {
        switch self {
        case .horologist: Color.white.opacity(0.28)
        case .inkwell: Color(red: 0.90, green: 0.75, blue: 0.40).opacity(0.22)
        case .playroom: Color.white.opacity(0.35)
        case .telemetry: Color(red: 1.0, green: 0.82, blue: 0.40).opacity(0.18)
        case .jelly: Color.white.opacity(0.55)
        }
    }

    var metalLite: Color {
        switch self {
        case .horologist: Palette.brassLite
        case .inkwell: Color(red: 0.22, green: 0.18, blue: 0.14)
        case .playroom: Color(red: 0.86, green: 0.68, blue: 0.40)
        case .telemetry: Color(red: 0.18, green: 0.16, blue: 0.14)
        case .jelly: Color(red: 1.0, green: 0.82, blue: 0.84)
        }
    }

    var metal: Color {
        switch self {
        case .horologist: Palette.brass
        case .inkwell: Color(red: 0.12, green: 0.10, blue: 0.08)
        case .playroom: Color(red: 0.72, green: 0.48, blue: 0.24)
        case .telemetry: Color(red: 0.10, green: 0.10, blue: 0.10)
        case .jelly: Color(red: 0.94, green: 0.62, blue: 0.70)
        }
    }

    var metalDark: Color {
        switch self {
        case .horologist: Palette.brassDark
        case .inkwell: Color(red: 0.05, green: 0.04, blue: 0.03)
        case .playroom: Color(red: 0.42, green: 0.24, blue: 0.10)
        case .telemetry: Color(red: 0.04, green: 0.04, blue: 0.04)
        case .jelly: Color(red: 0.72, green: 0.38, blue: 0.48)
        }
    }

    var well: Color {
        switch self {
        case .horologist: Color(red: 0.09, green: 0.07, blue: 0.05).opacity(0.92)
        case .inkwell: Color(red: 0.08, green: 0.06, blue: 0.04)
        case .playroom: Color(red: 0.78, green: 0.18, blue: 0.14)
        case .telemetry: Color.black
        case .jelly: Color.white.opacity(0.55)
        }
    }

    var numeral: Color {
        switch self {
        case .horologist: Palette.parchment
        case .inkwell: Color(red: 0.86, green: 0.70, blue: 0.32)
        case .playroom: Color(red: 0.99, green: 0.94, blue: 0.86)
        case .telemetry: Color(red: 1.0, green: 0.72, blue: 0.22)
        case .jelly: Color(red: 0.52, green: 0.22, blue: 0.32)
        }
    }
}

enum GlassSilhouette {
    case classic
    case column
    case toy
    case diamond
    case blob

    var metalID: Float {
        switch self {
        case .classic: 0
        case .column: 1
        case .toy: 2
        case .diamond: 3
        case .blob: 4
        }
    }
}
