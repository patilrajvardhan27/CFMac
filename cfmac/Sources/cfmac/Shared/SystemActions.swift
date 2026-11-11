import AppKit
import CfmacCore

/// Small AppKit side effects shared by several screens.
@MainActor
enum SystemActions {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openLoginItemsSettings() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    /// Opens a web search for `query` in the default browser. Nothing is sent until the user clicks.
    static func lookUp(_ query: String) {
        guard let url = WebLookup.searchURL(query) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Software with its own uninstaller (security, VPN, device management): search the web
    /// for the vendor's removal steps, so its system extensions are removed correctly too.
    static func lookUpUninstall(name: String) {
        lookUp(WebLookup.uninstallQuery(for: name))
    }

    private static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// The localized name of a running app that owns any of `owners` (bundle IDs or names).
    static func runningOwner(of owners: [String]) -> NSRunningApplication? {
        guard !owners.isEmpty else { return nil }
        let wanted = owners.map { $0.lowercased() }
        return NSWorkspace.shared.runningApplications.first { app in
            if let id = app.bundleIdentifier?.lowercased(), wanted.contains(id) { return true }
            guard let name = app.localizedName?.lowercased(), name.count >= 3 else { return false }
            return wanted.contains { $0.count >= 3 && ($0 == name || name.contains($0) || $0.contains(name)) }
        }
    }
}
