import Foundation

/// Shell scripts that install and remove the helper. They run once, as root, after the
/// user approves the macOS administrator prompt.
public enum HelperInstallScript {
    /// Human-readable list of every change installation makes, shown before asking for approval.
    public static func plannedChanges(uid: uid_t) -> [String] {
        [
            "Copy the helper to \(HelperLayout.executablePath) (owned by root)",
            "Add \(HelperLayout.launchdPlistPath) so macOS starts it at boot",
            "Start it; it listens on \(HelperLayout.socketPath) and only accepts requests from your account (user ID \(uid))",
            "macOS lists it under Login Items › Allow in the Background",
        ]
    }

    public static func launchdPlist(uid: uid_t) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(HelperLayout.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(HelperLayout.executablePath)</string>
                <string>--allowed-uid</string>
                <string>\(uid)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
        </dict>
        </plist>
        """
    }

    public static func install(helperSource: String, uid: uid_t) -> String {
        let label = HelperLayout.label
        return """
            set -eu
            /bin/launchctl bootout system/\(label) 2>/dev/null || true
            /bin/mkdir -p /Library/PrivilegedHelperTools
            /usr/bin/install -o root -g wheel -m 0755 \(quote(helperSource)) \(quote(HelperLayout.executablePath))
            /bin/cat > \(quote(HelperLayout.launchdPlistPath)) <<'CFMAC_PLIST'
            \(launchdPlist(uid: uid))
            CFMAC_PLIST
            /usr/sbin/chown root:wheel \(quote(HelperLayout.launchdPlistPath))
            /bin/chmod 0644 \(quote(HelperLayout.launchdPlistPath))
            for attempt in 1 2 3 4 5; do
              /bin/launchctl bootstrap system \(quote(HelperLayout.launchdPlistPath)) 2>/dev/null && break
              /bin/sleep 1
            done
            /bin/launchctl print system/\(label) >/dev/null
            """
    }

    /// Stopping the helper makes it return the fans to macOS before it exits.
    public static func uninstall() -> String {
        """
        /bin/launchctl bootout system/\(HelperLayout.label) 2>/dev/null || true
        /bin/rm -f \(quote(HelperLayout.launchdPlistPath)) \(quote(HelperLayout.executablePath)) \(quote(HelperLayout.socketPath))
        """
    }

    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
