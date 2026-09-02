import Foundation

enum TokenrashConfig {
    static let meURL = URL(string: "https://tokendash-backend-api-olut5dffgq-ew.a.run.app/me")!
    static let origin = URL(string: "https://tokendash-backend-api-olut5dffgq-ew.a.run.app")!
    static let pollInterval: TimeInterval = 180
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static let alarmSteps: [AlarmStep] = [
        AlarmStep(id: 10, remaining: 0.10, sound: .bell),
        AlarmStep(id: 5, remaining: 0.05, sound: .bells),
        AlarmStep(id: 1, remaining: 0.01, sound: .siren)
    ]

    struct AlarmStep {
        let id: Int
        let remaining: Double
        let sound: AlarmSound
    }

    enum AlarmSound {
        case bell, bells, siren
    }
}
