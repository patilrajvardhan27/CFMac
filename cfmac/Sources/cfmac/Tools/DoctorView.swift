import CfmacCore
import SwiftUI

struct DoctorView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var fan: FanController
    @Environment(\.dismiss) private var dismiss
    @Local private var copied = false
    @Local private var trashSize: Int64 = 0

    private var sections: [(title: String, lines: [String])] {
        let snapshot = monitor.snapshot
        var issues: [String] = []
        if snapshot.volume.total > 0, snapshot.volume.usedFraction > 0.9 { issues.append("Startup disk is at least 90% full. Open Clean to free up space.") }
        if !Permissions.hasFullDiskAccess { issues.append("Full Disk Access is off, so some items cannot be scanned or cleaned.") }
        if snapshot.pressure != .normal { issues.append("Memory pressure is elevated. Closing unused apps will help.") }
        if let health = snapshot.battery?.health, health < 80 { issues.append("Battery health is \(health)%. Consider a battery service check.") }
        if let cycles = snapshot.battery?.cycles, cycles > 1000 { issues.append("Battery has \(cycles) charge cycles.") }
        if trashSize > 5_000_000_000 { issues.append("Trash is over 5 GB. Empty it from Clean to reclaim space.") }
        if snapshot.uptime > 14 * 86_400 { issues.append("Up for \(Int(snapshot.uptime / 86_400)) days. Restarting usually frees memory.") }
        return [
            (
                "SYSTEM",
                [
                    "\(MachineInfo.chipName) · \(Format.bytes(snapshot.memory.total)) · \(MachineInfo.osVersion)",
                    "Uptime \(Format.duration(snapshot.uptime))",
                    "Disk \(Format.bytes(snapshot.volume.available)) free of \(Format.bytes(snapshot.volume.total))",
                    "Fans \(fan.fans.count) · CPU \(fan.temperatures.cpu.map { "\(Int($0))°C" } ?? "n/a")",
                ]
            ),
            (
                "PERMISSIONS",
                [
                    "Full Disk Access: \(Permissions.hasFullDiskAccess ? "Granted" : "Off")",
                    "Launch at login: \(AppSettings.shared.launchAtLogin ? "On" : "Off")",
                    "Fan helper: \(String(describing: fan.helperState))",
                ]
            ),
            (
                "ENVIRONMENT",
                [
                    "Homebrew: \(Shell.homebrew ?? "not installed")",
                    "mas: \(Shell.appStoreCLI ?? "not installed")",
                ]
            ),
            ("CFMAC", ["Version \(AppInfo.version)", Bundle.main.bundlePath]),
            ("DETECTED ISSUES", issues.isEmpty ? ["None"] : issues),
        ]
    }

    var body: some View {
        let report = sections
        VStack(alignment: .leading, spacing: 12) {
            Text("Doctor").font(.title2.bold())
            Text("Check your Mac and cfmac. Attach this report when reporting a problem.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(report, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(section.lines, id: \.self) { Text($0).textSelection(.enabled) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(copied ? "Copied" : "Copy Report") {
                    SystemActions.copy(report.map { "\($0.title)\n" + $0.lines.map { "  " + $0 }.joined(separator: "\n") }.joined(separator: "\n\n"))
                    copied = true
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 480)
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
        .task {
            await fan.checkHelper()
            trashSize = await Task.detached(priority: .utility) { DiskUsage.size(of: Paths.inHome(".Trash")) }.value
        }
    }
}
