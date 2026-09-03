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
        return pcmWAV(samples, sampleRate: sampleRate)
    }
}

enum FlapAudio {
    private static var playing: [NSSound] = []

    static func tick(variant: UInt64) {
        play(wav: flapWAV(variant: variant, land: false), volume: 0.38, keep: 0.18)
    }

    static func clack(variant: UInt64) {
        play(wav: flapWAV(variant: variant, land: true), volume: 0.52, keep: 0.22)
    }

    private static func play(wav: Data, volume: Float, keep: TimeInterval) {
        guard let sound = NSSound(data: wav) else { return }
        sound.volume = volume
        playing.append(sound)
        sound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + keep) {
            playing.removeAll { !$0.isPlaying }
        }
    }

    /// Short mechanical vane slap: noise burst + decaying thud, pitch-jittered per tile.
    private static func flapWAV(variant: UInt64, land: Bool, sampleRate: Int = 22_050) -> Data {
        let duration = land ? 0.068 : 0.042
        let count = Int(duration * Double(sampleRate))
        var samples = [Int16](repeating: 0, count: count)
        var rng = variant &* 0x9E3779B97F4A7C15
        func rand() -> Double {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1
            return Double(rng % 10_000) / 10_000
        }
        let thudFreq = (land ? 175.0 : 230.0) + rand() * 90
        let noiseAmp = land ? 0.58 : 0.36
        let thudAmp = land ? 0.48 : 0.26
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let noise = (rand() * 2 - 1) * noiseAmp * exp(-t * (land ? 52 : 78))
            let thud = sin(2 * Double.pi * thudFreq * t) * thudAmp * exp(-t * 36)
            let click = sin(2 * Double.pi * thudFreq * 3.2 * t) * 0.14 * exp(-t * 95)
            let sample = max(-1, min(1, noise + thud + click))
            samples[i] = Int16((sample * Double(Int16.max) * 0.9).rounded())
        }
        return pcmWAV(samples, sampleRate: sampleRate)
    }
}

private func pcmWAV(_ samples: [Int16], sampleRate: Int) -> Data {
    let dataSize = samples.count * 2
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
