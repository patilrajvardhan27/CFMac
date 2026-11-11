import Foundation
import Testing

@testable import SoundKit

@Suite("Completion sounds")
struct SoundKitTests {
    @Test(arguments: SynthEffect.allCases)
    func rendersAudibleNormalizedAudio(effect: SynthEffect) {
        let samples = SoundSynth.render(effect)
        let seconds = Double(samples.count) / Double(SoundSynth.sampleRate)
        #expect(seconds > 0.2 && seconds < 4)
        let finite = samples.allSatisfy { $0.isFinite }
        #expect(finite)
        let peak = samples.map(abs).max() ?? 0
        #expect(abs(peak - SoundSynth.peak) < 0.01)
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.02, "too quiet")
        // Faded edges: no click at the start or end.
        #expect(abs(samples.first ?? 1) < 0.01)
        #expect(abs(samples.last ?? 1) < 0.01)
    }

    @Test func renderingIsDeterministic() {
        #expect(SoundSynth.render(.fart) == SoundSynth.render(.fart))
    }

    @Test func mapsEverySoundToPlayback() {
        #expect(CompletionSound.none.playback() == .silent)
        #expect(CompletionSound.honey.playback() == .spoken(.honeyItsDone))
        #expect(CompletionSound.flush.playback() == .synthesized(.flush))
        #expect(CompletionSound.random.playback(pick: { _ in .burp }) == .synthesized(.burp))
        #expect(!CompletionSound.audible.contains(.random))
        #expect(!CompletionSound.audible.contains(.none))
        for _ in 0..<20 { #expect(CompletionSound.random.playback() != .silent) }
    }

    @Test func spokenLineIsValidSSML() throws {
        let document = try XMLDocument(xmlString: VoiceLine.honeyItsDone.ssml)
        #expect(document.rootElement()?.name == "speak")
    }

    @Test func encodesWAV() {
        let data = WAV.encode([0, 1, -1, 0.5], sampleRate: 8000)
        #expect(data.count == 44 + 8)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(data[44] == 0 && data[45] == 0)
        #expect(data[46] == 0xFF && data[47] == 0x7F)  // Int16.max, little-endian
    }
}

@Suite("Sound choices")
struct SoundChoiceTests {
    @Test(arguments: [
        SoundChoice.builtIn(.fart), .file(fileName: "A1.m4a", title: "Mine"), .spoken(text: "Done!", voiceIdentifier: nil),
    ])
    func choicesRoundTrip(choice: SoundChoice) throws {
        let data = try JSONEncoder().encode(choice)
        #expect(try JSONDecoder().decode(SoundChoice.self, from: data) == choice)
    }

    @Test func spokenLinesAreTrimmedAndLimited() {
        #expect(SoundChoice.cleanedSpokenText("  hi\nthere ") == "hi there")
        #expect(SoundChoice.cleanedSpokenText("   ") == nil)
        #expect(SoundChoice.cleanedSpokenText(String(repeating: "a", count: 200))?.count == SoundChoice.maximumSpokenLength)
        #expect(SoundChoice.builtIn(.none).isSilent)
    }

    @Test func importedSoundsAreValidated() {
        typealias Policy = ImportedSoundPolicy
        #expect(Policy.validate(fileExtension: "M4A", bytes: 100_000, seconds: 3, existingCount: 0) == nil)
        #expect(Policy.validate(fileExtension: "exe", bytes: 1, seconds: 1, existingCount: 0) == .unsupportedType)
        #expect(Policy.validate(fileExtension: "wav", bytes: 6 * 1_048_576, seconds: 1, existingCount: 0) == .tooLarge)
        #expect(Policy.validate(fileExtension: "wav", bytes: 1, seconds: 30, existingCount: 0) == .tooLong)
        #expect(Policy.validate(fileExtension: "wav", bytes: 1, seconds: nil, existingCount: 0) == .unreadable)
        #expect(Policy.validate(fileExtension: "wav", bytes: 1, seconds: 1, existingCount: 20) == .tooMany)
    }
}
