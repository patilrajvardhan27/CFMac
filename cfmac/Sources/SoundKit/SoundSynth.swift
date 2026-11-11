import Foundation

/// Sounds generated from scratch with simple oscillators, noise and filters.
public enum SynthEffect: String, CaseIterable, Sendable {
    case chime, tada, burp, fart, swoosh, flush, pop
}

/// Renders `SynthEffect`s to mono samples in -1...1. Output is deterministic.
public enum SoundSynth {
    public static let sampleRate = 44_100
    static let peak: Float = 0.85

    public static func render(_ effect: SynthEffect) -> [Float] {
        let raw: [Float] =
            switch effect {
            case .chime: chime()
            case .tada: tada()
            case .burp: burp()
            case .fart: fart()
            case .swoosh: swoosh()
            case .flush: flush()
            case .pop: pop()
            }
        return finish(raw)
    }

    // MARK: Effects

    /// Two bell strikes, a fifth apart.
    static func chime() -> [Float] {
        let notes: [(start: Double, frequency: Double)] = [(0, 1318.51), (0.14, 1975.53)]
        let partials: [(ratio: Double, gain: Double, decay: Double)] = [(1, 1, 3), (2.76, 0.4, 5), (5.4, 0.15, 8)]
        return synthesize(seconds: 1.6) { time in
            notes.reduce(0) { sum, note in
                let elapsed = time - note.start
                guard elapsed >= 0 else { return sum }
                let attack = min(1, elapsed / 0.004)
                return sum
                    + partials.reduce(0) { partialSum, partial in
                        partialSum + partial.gain * attack * exp(-elapsed * partial.decay) * sin(2 * .pi * note.frequency * partial.ratio * elapsed)
                    }
            }
        }
    }

    /// A short brass pickup chord, then a long major chord with vibrato.
    static func tada() -> [Float] {
        let chords: [(start: Double, length: Double, notes: [Double])] = [
            (0, 0.13, [392.00, 493.88, 587.33]),
            (0.16, 0.95, [523.25, 659.25, 783.99]),
        ]
        return synthesize(seconds: 1.25) { time in
            var sum = 0.0
            for chord in chords {
                let elapsed = time - chord.start
                guard elapsed >= 0, elapsed < chord.length else { continue }
                let attack = min(1, elapsed / 0.02)
                let release = min(1, (chord.length - elapsed) / 0.2)
                let vibrato = elapsed > 0.2 ? 1 + 0.004 * sin(2 * .pi * 5.5 * elapsed) : 1
                let brightness = min(1, elapsed / 0.06)
                var tone = 0.0
                for frequency in chord.notes {
                    for harmonic in 1...8 {
                        let n = Double(harmonic)
                        let gain: Double = pow(n, -1.2) * pow(brightness, n * 0.3)
                        tone += gain * sin(2 * .pi * frequency * vibrato * n * elapsed)
                    }
                }
                sum += tone * attack * release * (0.75 + 0.25 * exp(-elapsed * 6))
            }
            return sum
        }
    }

    /// A croaky glottal buzz through "uh" vowel formants, sliding down in pitch.
    static func burp() -> [Float] {
        let seconds = 1.0
        var noise = Noise(seed: 7)
        var formants = [ResonantFilter(), ResonantFilter(), ResonantFilter()]
        var breath = OnePole()
        var phase = 0.0
        var cycleGain: Float = 1
        var jitter = 0.0
        return synthesize(seconds: seconds) { time in
            let progress = time / seconds
            let frequency = 82 - 30 * progress + jitter
            phase += frequency / Double(sampleRate)
            if phase >= 1 {
                phase -= 1
                cycleGain = 0.55 + 0.45 * abs(noise.next())
                jitter = Double(noise.next()) * 4
            }
            // Sharp glottal pulse: open for 40% of the cycle.
            let pulse = phase < 0.4 ? pow(sin(.pi * phase / 0.4), 2) : 0
            let source = Float(pulse) * cycleGain
            let voiced =
                formants[0].bandPass(source, cutoff: 520, resonance: 6)
                + 0.6 * formants[1].bandPass(source, cutoff: 1150, resonance: 8)
                + 0.25 * formants[2].bandPass(source, cutoff: 2400, resonance: 10)
            let air = breath.lowPass(noise.next(), cutoff: 1500) * 0.08
            let envelope = min(1, time / 0.06) * min(1, (seconds - time) / 0.25) * (0.85 + 0.15 * sin(2 * .pi * 3 * time))
            return Double((voiced + air) * Float(envelope))
        }
    }

    /// A wobbling, rattling low buzz that rises and sputters out with a puff of air.
    static func fart() -> [Float] {
        let seconds = 1.35
        var noise = Noise(seed: 21)
        var body = ResonantFilter()
        var resonance = ResonantFilter()
        var puff = ResonantFilter()
        var phase = 0.0
        var drift = 0.0
        return synthesize(seconds: seconds) { time in
            drift = drift * 0.9995 + Double(noise.next()) * 0.04
            let rising = time > 0.85 ? (time - 0.85) * 90 : 0
            let frequency = 92 + 16 * sin(2 * .pi * 11 * time) + drift * 6 + rising
            phase = (phase + frequency / Double(sampleRate)).truncatingRemainder(dividingBy: 1)
            let pulse: Float = phase < 0.3 ? 1 : -0.43
            let raw = pulse + noise.next() * 0.25
            let buzz = body.lowPass(raw, cutoff: 700, resonance: 2.5) + 0.8 * resonance.bandPass(raw, cutoff: 220, resonance: 3)
            let flutter = 0.75 + 0.25 * sin(2 * .pi * 23 * time)
            let sputter = time > 0.85 ? (sin(2 * .pi * 17 * time) > -0.2 ? 1.0 : 0.15) : 1.0
            let envelope = min(1, time / 0.03) * flutter * sputter * min(1, max(0, (1.12 - time) / 0.12))
            let puffTime = time - 1.12
            let air = puffTime > 0 ? puff.highPass(noise.next(), cutoff: 900, resonance: 0.8) * Float(exp(-puffTime * 18) * 0.5) : 0
            return Double(buzz * Float(envelope) + air)
        }
    }

    /// Filtered noise sweeping up and back down: something rushing past.
    static func swoosh() -> [Float] {
        let seconds = 0.7
        var noise = Noise(seed: 3)
        var filter = ResonantFilter()
        return synthesize(seconds: seconds) { time in
            let progress = time / seconds
            let cutoff = 300 + 5500 * pow(sin(.pi * progress), 2)
            let shaped = filter.process(noise.next(), cutoff: cutoff, resonance: 1.8)
            let envelope = progress < 0.35 ? pow(progress / 0.35, 2) : exp(-(progress - 0.35) * 6)
            return Double((shaped.band + 0.3 * shaped.low) * Float(envelope))
        }
    }

    /// Lever clunk, rushing water with gurgles, a draining swirl and a final glug.
    static func flush() -> [Float] {
        let seconds = 3.2
        var noise = Noise(seed: 11)
        var water = ResonantFilter()
        var swirl = ResonantFilter()
        var click = ResonantFilter()
        var bubbles: [(start: Double, frequency: Double, length: Double)] = []
        var bubbleNoise = Noise(seed: 99)
        var next = 0.5
        while next < 2.8 {
            bubbles.append((next, 350 + 350 * Double(abs(bubbleNoise.next())), 0.03 + 0.03 * Double(abs(bubbleNoise.next()))))
            next += 0.05 + 0.18 * Double(abs(bubbleNoise.next()))
        }
        return synthesize(seconds: seconds) { time in
            let white = noise.next()
            // Lever: a click and a low thunk.
            let lever =
                time < 0.08
                ? Double(click.highPass(white, cutoff: 2000, resonance: 0.7)) * exp(-time * 120) + 0.6 * sin(2 * .pi * 120 * time) * exp(-time * 40)
                : 0
            // Rushing water swells, holds, then drains.
            let swell = min(1, max(0, (time - 0.15) / 0.45)) * min(1, max(0, (3.0 - time) / 1.0))
            let rush = water.lowPass(white, cutoff: 900 + 400 * sin(2 * .pi * 0.7 * time), resonance: 1)
            // Draining whirl: a resonant band sweeping downward.
            let whirlProgress = min(1, max(0, (time - 1.8) / 1.2))
            let whirlLevel = whirlProgress > 0 ? sin(.pi * whirlProgress) : 0
            let whirl = swirl.bandPass(white, cutoff: 1200 - 950 * whirlProgress, resonance: 3)
            // Gurgles: short rising sine chirps.
            let gurgle = bubbles.reduce(0.0) { sum, bubble in
                let elapsed = time - bubble.start
                guard elapsed >= 0, elapsed < bubble.length else { return sum }
                let frequency = bubble.frequency * (1 + 0.5 * elapsed / bubble.length)
                return sum + sin(2 * .pi * frequency * elapsed) * exp(-elapsed * 50) * 0.35
            }
            let glugTime = time - 2.9
            let glug = glugTime > 0 && glugTime < 0.2 ? sin(2 * .pi * (180 - 450 * glugTime) * glugTime) * exp(-glugTime * 15) * 0.6 : 0
            return lever + Double(rush) * swell * 0.9 + Double(whirl) * whirlLevel * 1.2 + gurgle + glug
        }
    }

    /// A bubble popping: a fast upward chirp with a tiny click.
    static func pop() -> [Float] {
        var noise = Noise(seed: 5)
        return synthesize(seconds: 0.3) { time in
            let pops: [(start: Double, gain: Double)] = [(0, 1), (0.1, 0.55)]
            return pops.reduce(0) { sum, pop in
                let elapsed = time - pop.start
                guard elapsed >= 0 else { return sum }
                let frequency = 280 * pow(4, min(1, elapsed / 0.035))
                let body = sin(2 * .pi * frequency * elapsed) * exp(-elapsed * 40) * min(1, elapsed / 0.002)
                let snap = elapsed < 0.003 ? Double(noise.next()) * 0.6 : 0
                return sum + (body + snap) * pop.gain
            }
        }
    }

    // MARK: Helpers

    private static func synthesize(seconds: Double, _ sample: (Double) -> Double) -> [Float] {
        let count = Int(seconds * Double(sampleRate))
        return (0..<count).map { index in Float(sample(Double(index) / Double(sampleRate))) }
    }

    /// Fades the edges to avoid clicks, then normalizes to a common peak level.
    static func finish(_ samples: [Float]) -> [Float] {
        let fade = min(samples.count / 2, sampleRate / 200)
        let faded = samples.enumerated().map { index, value in
            let edge = min(index, samples.count - 1 - index)
            return edge < fade ? value * Float(edge) / Float(fade) : value
        }
        guard let loudest = faded.lazy.map(abs).max(), loudest > 0, loudest.isFinite else { return faded }
        let scale = peak / loudest
        return faded.map { $0 * scale }
    }
}

/// Deterministic white noise in -1...1 (xorshift).
struct Noise {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(Double(state >> 11) / Double(1 << 53) * 2 - 1)
    }
}

/// One-pole low-pass filter.
struct OnePole {
    private var value: Float = 0

    mutating func lowPass(_ input: Float, cutoff: Double) -> Float {
        let coefficient = Float(1 - exp(-2 * .pi * cutoff / Double(SoundSynth.sampleRate)))
        value += coefficient * (input - value)
        return value
    }
}

/// Chamberlin state-variable filter with low, band and high outputs.
struct ResonantFilter {
    private var low: Float = 0
    private var band: Float = 0

    mutating func process(_ input: Float, cutoff: Double, resonance: Double) -> (low: Float, band: Float, high: Float) {
        // Stable while the cutoff stays below a sixth of the sample rate.
        let limited = min(cutoff, Double(SoundSynth.sampleRate) / 6)
        let frequency = Float(2 * sin(.pi * limited / Double(SoundSynth.sampleRate)))
        let damping = Float(1 / max(0.5, resonance))
        low += frequency * band
        let high = input - low - damping * band
        band += frequency * high
        return (low, band, high)
    }

    mutating func lowPass(_ input: Float, cutoff: Double, resonance: Double = 0.707) -> Float {
        process(input, cutoff: cutoff, resonance: resonance).low
    }

    mutating func bandPass(_ input: Float, cutoff: Double, resonance: Double) -> Float {
        process(input, cutoff: cutoff, resonance: resonance).band
    }

    mutating func highPass(_ input: Float, cutoff: Double, resonance: Double) -> Float {
        process(input, cutoff: cutoff, resonance: resonance).high
    }
}

/// 16-bit mono PCM WAV encoding.
public enum WAV {
    public static func encode(_ samples: [Float], sampleRate: Int = SoundSynth.sampleRate) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let payload = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + payload))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))  // bytes per second
        append(UInt16(2))  // block align
        append(UInt16(16))  // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(payload))
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
