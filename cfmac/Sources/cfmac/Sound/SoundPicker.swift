import AVFoundation
import AppKit
import SoundKit
import SwiftUI

/// A grid of sound choices: built-ins, the user's own sounds, and tiles to add more.
/// Tapping a tile selects it and plays a preview.
struct SoundPicker: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var selection: SoundChoice
    var columns = 5
    @Local private var showsSpokenLine = false
    @Local private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(CompletionSound.allCases) { sound in tile(.builtIn(sound)) }
                ForEach(settings.savedSounds, id: \.self) { choice in
                    tile(choice).contextMenu {
                        Button("Remove", role: .destructive) { remove(choice) }
                    }
                }
                addTile("Import…", symbol: "square.and.arrow.down", action: importFile)
                addTile("Type a line…", symbol: "text.bubble", action: { showsSpokenLine = true })
            }
            if let importError {
                Text(importError).font(.caption).foregroundStyle(Color.accentAmber)
            }
        }
        .sheet(isPresented: $showsSpokenLine) {
            SpokenLineSheet { choice in
                settings.savedSounds.append(choice)
                choose(choice)
            }
            .environmentObject(settings)
        }
    }

    private func tile(_ choice: SoundChoice) -> some View {
        let isSelected = selection == choice
        return Button {
            choose(choice)
        } label: {
            TileLabel(emoji: choice.emoji, title: choice.title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func addTile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ choice: SoundChoice) {
        selection = choice
        SoundPlayer.shared.play(choice)
    }

    private func remove(_ choice: SoundChoice) {
        CustomSoundLibrary.delete(choice)
        settings.savedSounds.removeAll { $0 == choice }
        if settings.soundChoice == choice { settings.soundChoice = .builtIn(.chime) }
        for (job, sound) in settings.jobSounds where sound == choice { settings.jobSounds[job] = nil }
    }

    /// Only the one file the user picks is read, and it is copied into cfmac's own folder.
    private func importFile() {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a short sound (AIFF, CAF, M4A, MP3 or WAV, up to 15 seconds)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch CustomSoundLibrary.importSound(from: url) {
        case .success(let choice):
            settings.savedSounds.append(choice)
            choose(choice)
        case .failure(let rejection):
            importError = rejection.message
        }
    }
}

private struct TileLabel: View {
    let emoji: String
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 22))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Color.accentBlue.opacity(0.25) : Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isSelected ? Color.accentBlue : .clear, lineWidth: 1.5))
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(Motion.value, value: isSelected)
        .contentShape(Rectangle())
    }
}

/// Type your own "done" line and pick the voice that says it.
struct SpokenLineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (SoundChoice) -> Void
    @Local private var text = "All done, superstar!"
    @Local private var voiceIdentifier: String = SoundPlayer.preferredVoice?.identifier ?? ""

    private var choice: SoundChoice? {
        SoundChoice.cleanedSpokenText(text).map { .spoken(text: $0, voiceIdentifier: voiceIdentifier.isEmpty ? nil : voiceIdentifier) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your own “done” line").font(.title3.bold())
            TextField("What should your Mac say?", text: $text)
                .textFieldStyle(.roundedBorder)
            Text("Up to \(SoundChoice.maximumSpokenLength) characters. Spoken by a voice on your Mac; nothing is sent anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Voice", selection: $voiceIdentifier) {
                ForEach(SoundPlayer.voices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                }
            }
            HStack {
                Button("Preview") { if let choice { SoundPlayer.shared.play(choice) } }
                    .disabled(choice == nil)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let choice { onSave(choice) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(choice == nil)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// Compact menu for picking a sound, used for per-job choices and the top-left pill.
struct SoundChoiceMenu<MenuLabel: View>: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var selection: SoundChoice
    @ViewBuilder var label: MenuLabel

    var body: some View {
        Menu {
            ForEach(CompletionSound.allCases) { sound in item(.builtIn(sound)) }
            if !settings.savedSounds.isEmpty {
                Divider()
                ForEach(settings.savedSounds, id: \.self) { item($0) }
            }
            Divider()
            Button("Play Preview") { SoundPlayer.shared.play(selection) }
                .disabled(selection.isSilent)
        } label: {
            label
        }
    }

    private func item(_ choice: SoundChoice) -> some View {
        Button {
            selection = choice
            SoundPlayer.shared.play(choice)
        } label: {
            if choice == selection {
                Label("\(choice.emoji)  \(choice.title)", systemImage: "checkmark")
            } else {
                Text("\(choice.emoji)  \(choice.title)")
            }
        }
    }
}

/// Top-left pill on every screen: shows the current "done" sound and lets you change it.
struct SoundMenuPill: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SoundChoiceMenu(selection: $settings.soundChoice) {
            HStack(spacing: 6) {
                Text(settings.soundChoice.emoji)
                Text(settings.soundChoice.isSilent ? "Sound off" : settings.soundChoice.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.ink.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Color.ink.opacity(0.15)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: 220, alignment: .leading)
        .help("Sound played when a job is done")
    }
}
