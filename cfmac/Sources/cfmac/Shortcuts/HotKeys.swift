import AppKit
import Carbon.HIToolbox
import CfmacCore
import SwiftUI

/// Global keyboard shortcuts through Carbon hot keys, which need no Accessibility or
/// Input Monitoring permission: macOS delivers only the registered key combinations.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private static let signature: OSType = 0x6366_6D63  // "cfmc"

    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: ShortcutAction] = [:]
    private var handler: EventHandlerRef?

    func reload() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        actions.removeAll()
        installHandlerIfNeeded()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let combo = AppSettings.shared.shortcuts[action], combo.isValidGlobal else { continue }
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            if RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr, let reference {
                registered.append(reference)
                actions[UInt32(index)] = action
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKey = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
                guard status == noErr else { return status }
                let id = hotKey.id
                Task { @MainActor in HotKeyCenter.shared.fire(id) }
                return noErr
            }, 1, &spec, nil, &handler)
    }

    private func fire(_ id: UInt32) {
        guard let action = actions[id] else { return }
        perform(action)
    }

    func perform(_ action: ShortcutAction) {
        let models = AppModels.shared
        switch action {
        case .showWindow:
            WindowOpener.showMain()
        case .commandPalette:
            WindowOpener.showMain()
            models.router.showsPalette = true
        case .scan:
            WindowOpener.showMain()
            models.router.tab = .clean
            models.clean.scan()
        case .keepAwake:
            models.awake.isActive ? models.awake.stop() : models.awake.start(minutes: nil)
        case .cleanScreen:
            CleanScreen.shared.start()
        }
    }
}

/// Click, then press the shortcut. Escape cancels; the trash button clears it.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @Local private var isRecording = false
    @Local private var monitor: Any?
    @Local private var hint: String?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? "Press keys…" : (combo?.display ?? "Record Shortcut")) {
                isRecording ? stop() : start()
            }
            .frame(minWidth: 130)
            if combo != nil {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Turn off this shortcut")
            }
            if let hint { Text(hint).font(.caption).foregroundStyle(Color.accentAmber) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { capture(event) }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func capture(_ event: NSEvent) {
        defer { stop() }
        if event.keyCode == UInt16(kVK_Escape) { return }
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= KeyCombo.command }
        if flags.contains(.shift) { modifiers |= KeyCombo.shift }
        if flags.contains(.option) { modifiers |= KeyCombo.option }
        if flags.contains(.control) { modifiers |= KeyCombo.control }
        let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: Self.name(for: event))
        guard candidate.isValidGlobal else {
            hint = "Use 2+ modifiers"
            return
        }
        combo = candidate
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Delete: "⌫", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func name(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        return (event.charactersIgnoringModifiers ?? "").uppercased()
    }
}
