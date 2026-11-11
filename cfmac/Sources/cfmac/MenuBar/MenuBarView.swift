import AppKit
import CfmacCore
import FanService
import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var awake: KeepAwake
    @EnvironmentObject private var stats: UsageStats
    @EnvironmentObject private var fan: FanController
    @EnvironmentObject private var settings: AppSettings
    @Local private var ejectMessage: String?
    @Local private var showsRunners = false

    var body: some View {
        let snapshot = monitor.snapshot
        let health = monitor.health
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("cfmac").font(.headline)
                Spacer()
                Text("Health \(health.score) · \(health.label)").font(.caption).foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    tile("CPU", "\(Format.percent(snapshot.cpu))%", monitor.cpuHistory, .accentGreen)
                    tile("Memory", "\(Format.percent(snapshot.memory.fraction))%", monitor.memoryHistory, .accentAmber)
                }
                GridRow {
                    tile("Free space", Format.bytes(snapshot.volume.available), nil, .accentBlue)
                    tile("Network", "↓" + Format.rate(snapshot.network.download), monitor.networkHistory, .accentBlue)
                }
            }
            if let battery = snapshot.battery {
                Label("\(battery.percent)% · \(battery.statusText)", systemImage: battery.isCharging ? "battery.100.bolt" : "battery.75")
                    .font(.system(size: 12))
            }
            if fan.hasFans, fan.isEnabled {
                HStack {
                    Label("Fan \(Int(fan.fans.map(\.rpm).max() ?? 0)) RPM", systemImage: "fan").font(.system(size: 12))
                    Spacer()
                    Picker("Fan mode", selection: Binding(get: { fan.mode }, set: { mode in Task { await fan.select(mode) } })) {
                        ForEach(FanMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }

            Text("TOP PROCESSES").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            ForEach(snapshot.processes.sorted { $0.cpu > $1.cpu }.prefix(5)) { process in
                HStack {
                    if let app = process.appPath { AppIcon(path: app, size: 14) }
                    Text(process.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%%", process.cpu))
                        .monospacedDigit()
                        .foregroundStyle(process.cpu > 80 ? Color.accentRed : .secondary)
                }
                .font(.system(size: 12))
            }

            Divider()
            HStack(spacing: 8) {
                quickAction(awake.isActive ? "Awake On" : "Awake", symbol: "cup.and.saucer", isActive: awake.isActive) {
                    awake.isActive ? awake.stop() : awake.start(minutes: nil)
                }
                .contextMenu {
                    ForEach([15, 30, 60, 120], id: \.self) { minutes in Button("\(minutes) min") { awake.start(minutes: minutes) } }
                    Button("Until stopped") { awake.start(minutes: nil) }
                }
                quickAction("Screen", symbol: "sparkles.tv") { CleanScreen.shared.start() }
                quickAction("Eject", symbol: "eject") {
                    let failed = Ejector.ejectAll()
                    ejectMessage = failed.isEmpty ? "Ejected" : "Could not eject: " + failed.joined(separator: ", ")
                }
            }
            if let ejectMessage { Text(ejectMessage).font(.caption).foregroundStyle(.secondary) }

            Divider()
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsRunners.toggle() }
            } label: {
                HStack(spacing: 8) {
                    AnimatedRunner(runner: settings.runner, height: 14)
                    Text("Runner · \(settings.runner.title)").font(.system(size: 12))
                    Spacer()
                    Image(systemName: showsRunners ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change the animal in the menu bar")
            if showsRunners { RunnerGrid(columns: 5) }

            Divider()
            HStack {
                Text(stats.bytesCleaned > 0 ? "Cleaned \(Format.bytes(stats.bytesCleaned)) · \(stats.optimizeRuns)× optimized" : "Ready to clean")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    WindowOpener.showMain()
                    AppModels.shared.router.showsStatsCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share my stats")
                Button("Open cfmac") { WindowOpener.showMain() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 330)
    }

    private func tile(_ title: String, _ value: String, _ history: [Double]?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
            if let history {
                Sparkline(values: history, tint: tint).frame(height: 18)
            } else {
                Spacer().frame(height: 18)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func quickAction(_ title: String, symbol: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isActive ? Color.accentGreen.opacity(0.3) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
