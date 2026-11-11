import AppKit
import IOKit.pwr_mgt
import SwiftUI
import UserNotifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Keep Screen On ("Awake"): holds power assertions until stopped or the timer ends.
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()

    @Published private(set) var isActive = false
    @Published private(set) var endsAt: Date?
    private var assertions: [IOPMAssertionID] = []
    private var timer: Timer?

    func start(minutes: Int?) {
        release()
        let types: [String] =
            switch AppSettings.shared.keepAwakeMode {
            case .displayOnly: [kIOPMAssertionTypePreventUserIdleDisplaySleep]
            case .displayAndSystem: [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep]
            case .systemOnly: [kIOPMAssertionTypePreventUserIdleSystemSleep]
            }
        for type in types {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "cfmac Keep Screen On" as CFString, &id)
                == kIOReturnSuccess
            {
                assertions.append(id)
            }
        }
        isActive = !assertions.isEmpty
        guard isActive else { return }
        if let minutes {
            endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { _ in
                MainActor.assumeIsolated { KeepAwake.shared.stop() }
            }
            Notifier.post(title: "Awake is on", body: "Screen will stay on for \(minutes) min.")
        } else {
            Notifier.post(title: "Awake is on", body: "Screen will stay on until you turn Awake off.")
        }
    }

    func stop() {
        let wasActive = isActive
        release()
        if wasActive { Notifier.post(title: "Awake is off", body: "Normal sleep settings are restored.") }
    }

    /// Ends the assertions without notifying (used when quitting).
    func release() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions = []
        timer?.invalidate()
        timer = nil
        isActive = false
        endsAt = nil
    }
}

/// Clean Screen: blacks out every display and swallows keystrokes so the screen and
/// keyboard can be wiped. Holding Escape for 1.5 seconds exits.
@MainActor
final class CleanScreen: ObservableObject {
    static let shared = CleanScreen()
    private static let escapeKey: UInt16 = 53
    private static let holdToExit: TimeInterval = 1.5

    @Published private(set) var isActive = false
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var escapeDown: Date?
    private var timer: Timer?

    func start() {
        guard !isActive else { return }
        isActive = true
        let seconds = AppSettings.shared.cleanScreenSeconds
        let deadline = seconds > 0 ? Date().addingTimeInterval(TimeInterval(seconds)) : nil
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: CleanScreenOverlay(deadline: deadline))
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            window.animator().alphaValue = 1
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.hide()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
        if let deadline {
            timer = Timer.scheduledTimer(withTimeInterval: deadline.timeIntervalSinceNow, repeats: false) { _ in
                MainActor.assumeIsolated { CleanScreen.shared.stop() }
            }
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == Self.escapeKey else { return }
        switch event.type {
        case .keyDown:
            let pressed = escapeDown ?? Date()
            escapeDown = pressed
            if Date().timeIntervalSince(pressed) > Self.holdToExit { stop() }
        case .keyUp:
            escapeDown = nil
        default:
            break
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timer?.invalidate()
        timer = nil
        escapeDown = nil
        NSCursor.unhide()
    }
}

private struct CleanScreenOverlay: View {
    let deadline: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack {
                Spacer()
                Text(footer(now: context.date))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    private func footer(now: Date) -> String {
        guard let deadline else { return "Screen and keyboard locked · Hold Esc to exit" }
        return "Screen and keyboard locked · exits in \(max(0, Int(deadline.timeIntervalSince(now))))s · Hold Esc to exit"
    }
}

enum Ejector {
    @MainActor
    static func ejectAll() -> [String] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .filter { url in
                guard url.path != "/", let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
                return values.volumeIsEjectable == true || values.volumeIsRemovable == true || values.volumeIsInternal == false
            }
        return volumes.compactMap { url in
            (try? NSWorkspace.shared.unmountAndEjectDevice(at: url)) == nil ? url.lastPathComponent : nil
        }
    }
}
