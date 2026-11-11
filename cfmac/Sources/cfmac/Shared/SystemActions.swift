import AppKit

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

    /// Explains, locally, how to remove software that ships its own uninstaller. No web lookup.
    static func showVendorUninstallHelp(for appPath: String, name: String) {
        let alert = NSAlert()
        alert.messageText = "\(name) has its own uninstaller"
        alert.informativeText = """
            Security, VPN and device-management software must be removed with the vendor's tool so its \
            system extensions are cleaned up correctly. Look for an "Uninstall" app next to \(name), in \
            /Applications/Utilities, or in the installer you downloaded.
            """
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn { reveal(appPath) }
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
