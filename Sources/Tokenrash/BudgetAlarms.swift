import AppKit
import Foundation

@MainActor
final class BudgetAlarms {
    var onTrip: (() -> Void)?

    private let lastKey = "alarms.lastRemaining"
    private let firedKey = "alarms.fired"

    func observe(remaining: Double) {
        let current = min(1, max(0, remaining))
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: lastKey) as? Double

        if let stored, current > stored + 0.08 {
            defaults.removeObject(forKey: firedKey)
        }

        var fired = Set(defaults.array(forKey: firedKey) as? [Int] ?? [])
        guard let previous = stored else {
            for step in TokenrashConfig.alarmSteps where current <= step.remaining {
                fired.insert(step.id)
            }
            defaults.set(current, forKey: lastKey)
            defaults.set(Array(fired), forKey: firedKey)
            return
        }

        var tripped: TokenrashConfig.AlarmStep?
        for step in TokenrashConfig.alarmSteps {
            if previous > step.remaining, current <= step.remaining, !fired.contains(step.id) {
                fired.insert(step.id)
                tripped = step
            }
        }

        defaults.set(current, forKey: lastKey)
        defaults.set(Array(fired), forKey: firedKey)

        guard let tripped else { return }
        onTrip?()
        AlarmAudio.play(tripped.sound)
    }
}

enum AlarmAudio {
    private static var current: NSSound?
    private static var followUp: DispatchWorkItem?

    static func play(_ sound: TokenrashConfig.AlarmSound) {
        followUp?.cancel()
        switch sound {
        case .bell:
            ring(times: 1)
        case .bells:
            ring(times: 2)
        case .siren:
            playSound(NSSound(data: sirenWAV()) ?? NSSound(named: "Sosumi"))
        }
    }

    private static func ring(times: Int) {
        playSound(NSSound(named: "Glass"))
        guard times > 1 else { return }
        let work = DispatchWorkItem {
            playSound(NSSound(named: "Glass"))
        }
        followUp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
    }

    private static func playSound(_ sound: NSSound?) {
        current?.stop()
        current = sound
        current?.volume = 1
        current?.play()
    }

    /// Two-tone electronic siren, a few seconds, no bundled asset.
    private static func sirenWAV(duration: Double = 3.6, sampleRate: Int = 22_050) -> Data {
        let count = Int(duration * Double(sampleRate))
        var samples = [Int16](repeating: 0, count: count)
        var phase = 0.0
        let twoPi = 2.0 * Double.pi
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let cycle = t.truncatingRemainder(dividingBy: 0.64)
            let freq = cycle < 0.32 ? 880.0 : 554.0
            phase += twoPi * freq / Double(sampleRate)
            if phase > twoPi { phase -= twoPi }
            let attack = min(1, t * 10)
            let release = min(1, (duration - t) * 5)
            let sample = sin(phase) * 0.62 * attack * release
            samples[i] = Int16((max(-1, min(1, sample)) * Double(Int16.max)).rounded())
        }

        let dataSize = count * 2
        var data = Data(capacity: 44 + dataSize)
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        func u32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }

        ascii("RIFF")
        u32(UInt32(36 + dataSize))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(dataSize))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
