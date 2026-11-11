import CfmacCore
import FanService
import SwiftUI

struct StatusView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var fan: FanController
    @EnvironmentObject private var settings: AppSettings
    @Local private var customizing = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private static let cardHeight: CGFloat = 174

    private var visibleCards: [StatusCard] { settings.statusCards.filter { !settings.hiddenStatusCards.contains($0) } }

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(Array(visibleCards.enumerated()), id: \.element) { index, card in
                    cardView(card).frame(height: Self.cardHeight).appearEffect(order: index)
                }
            }
            .animation(Motion.content, value: visibleCards)
            ProcessTable().appearEffect(order: visibleCards.count)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .overlay(alignment: .topTrailing) {
            Button {
                customizing = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondaryText)
            .padding(.top, -26)
            .padding(.trailing, 20)
            .help("Arrange and hide cards")
        }
        .sheet(isPresented: $customizing) { StatusCustomizeSheet().environmentObject(settings) }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
        // Fan readings and the helper lease are kept current by FanController's own loop.
        .task { await fan.refresh() }
    }

    @ViewBuilder
    private func cardView(_ card: StatusCard) -> some View {
        switch card {
        case .health: HealthCard()
        case .cpu: CPUCard()
        case .gpu: GPUCard()
        case .memory: MemoryCard()
        case .battery: BatteryCard()
        case .disk: DiskCard()
        case .network: NetworkCard()
        case .fan: FanCard()
        }
    }
}

/// Reorder (drag) and show or hide Status cards.
struct StatusCustomizeSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arrange Status").font(.title3.bold())
            Text("Drag to reorder. Turn a card off to hide it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(settings.statusCards) { card in
                    Toggle(
                        card.title,
                        isOn: Binding(
                            get: { !settings.hiddenStatusCards.contains(card) },
                            set: { visible in
                                if visible { settings.hiddenStatusCards.remove(card) } else { settings.hiddenStatusCards.insert(card) }
                            }
                        ))
                }
                .onMove { settings.statusCards.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 300)
            HStack {
                Button("Reset") {
                    settings.statusCards = StatusCard.allCases
                    settings.hiddenStatusCards = []
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private func temperatureText(_ value: Double?) -> String? {
    value.map { "\(Int($0.rounded()))°C" }
}

private struct CardFooter: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color.secondaryText).lineLimit(1)
    }
}

private struct HealthCard: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let health = monitor.health
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "sun.max", title: "Health")
                    Spacer()
                    Chip(text: MachineInfo.chipName)
                    Chip(text: Format.bytes(monitor.snapshot.memory.total))
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        BigValue(value: "\(health.score)", unit: health.label)
                        Text(health.headline)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryText)
                            .help(
                                health.penalties.isEmpty ? "No penalties" : health.penalties.map { "\($0.reason), −\($0.points) pts" }.joined(separator: "\n"))
                    }
                    Spacer()
                    HaloPlanetView(planet: settings.planet(for: .health), diameter: 76)
                }
                Spacer(minLength: 0)
                CardFooter(text: "up \(Format.duration(monitor.snapshot.uptime)) · \(MachineInfo.osVersion)")
            }
        }
    }
}

private struct CPUCard: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var fan: FanController

    var body: some View {
        let snapshot = monitor.snapshot
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "cpu", title: "CPU")
                    Spacer()
                    if let temperature = temperatureText(fan.temperatures.cpu) { Chip(text: temperature) }
                }
                BigValue(value: "\(Format.percent(snapshot.cpu))", unit: "%")
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(snapshot.cpuCores.sorted(by: >).enumerated()), id: \.offset) { _, load in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.accentGreen.opacity(0.75))
                            .frame(height: max(3, 40 * load))
                    }
                }
                .frame(height: 40, alignment: .bottom)
                .animation(Motion.value, value: snapshot.cpuCores)
                Spacer(minLength: 0)
                CardFooter(text: "\(loadWord(snapshot.cpu)) · \(snapshot.cpuCores.count) cores · Load avg \(String(format: "%.1f", snapshot.loadAverage))")
            }
        }
    }

    private func loadWord(_ cpu: Double) -> String {
        switch cpu {
        case 0.85...: "heavy"
        case 0.5..<0.85: "busy"
        case 0.15..<0.5: "normal"
        default: "idle"
        }
    }
}

private struct GPUCard: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var fan: FanController

    var body: some View {
        let gpu = monitor.snapshot.gpu
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "square.stack.3d.down.right", title: "GPU")
                    Spacer()
                    if let temperature = temperatureText(fan.temperatures.gpu) { Chip(text: temperature) }
                }
                BigValue(value: gpu.map { "\(Format.percent($0))" } ?? "--", unit: "%")
                Sparkline(values: monitor.gpuHistory, tint: .accentAmber, filled: false).frame(height: 36)
                Spacer(minLength: 0)
                CardFooter(text: (gpu ?? 0) > 0.3 ? "busy" : "idle")
            }
        }
    }
}

private struct MemoryCard: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        let snapshot = monitor.snapshot
        let (label, tint): (String, Color) =
            switch snapshot.pressure {
            case .critical: ("Pressure critical", .accentRed)
            case .warning: ("Pressure high", .accentAmber)
            case .normal: ("Pressure normal", .accentGreen)
            }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "memorychip", title: "Memory")
                    Spacer()
                    Chip(text: label, tint: tint)
                }
                BigValue(value: "\(Format.percent(snapshot.memory.fraction))", unit: "%")
                Sparkline(values: monitor.memoryHistory, tint: Color(hex: 0xE8D2A8)).frame(height: 36)
                Spacer(minLength: 0)
                CardFooter(text: "\(Format.bytes(snapshot.memory.used)) · \(Format.bytes(snapshot.memory.swapUsed)) swap")
            }
        }
    }
}

private struct BatteryCard: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "battery.100", title: "Battery")
                    Spacer()
                    if let health = monitor.snapshot.battery?.health {
                        Chip(text: "\(health)% Health", tint: health < 80 ? .accentAmber : .ink)
                    }
                }
                if let battery = monitor.snapshot.battery {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        BigValue(value: "\(battery.percent)", unit: "%")
                        if battery.isCharging { Image(systemName: "bolt.fill").foregroundStyle(Color.accentGreen) }
                        if battery.isPluggedIn, let watts = battery.adapterWatts {
                            Text("\(watts)W").font(.system(size: 13)).foregroundStyle(Color.secondaryText)
                        }
                    }
                    CardFooter(text: battery.statusText)
                    Spacer(minLength: 0)
                    CardFooter(
                        text: [
                            battery.cycles.map { "\($0) cycles" },
                            battery.temperature.map { "\(Int($0.rounded()))°C" },
                            battery.condition.flatMap { $0 == "Good" ? nil : $0 },
                        ].compactMap { $0 }.joined(separator: " · "))
                } else {
                    BigValue(value: "AC", unit: "power")
                    Spacer(minLength: 0)
                    CardFooter(text: "This Mac has no internal battery")
                }
            }
        }
    }
}

private struct DiskCard: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        let volume = monitor.snapshot.volume
        let free = Format.bytesParts(volume.available)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "internaldrive", title: "Free space")
                    Spacer()
                    Chip(text: Format.bytes(volume.total))
                }
                BigValue(value: free.number, unit: free.unit)
                MeterBar(fraction: volume.usedFraction, tint: .accentBlue).padding(.top, 8)
                Spacer(minLength: 0)
                CardFooter(text: "\(Format.bytes(volume.used)) used · \(Format.percent(volume.usedFraction))%")
                    .help("Free space includes space macOS can reclaim when needed.")
            }
        }
    }
}

private struct NetworkCard: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        let network = monitor.snapshot.network
        let download = Format.rateParts(network.download)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "globe", title: "Network")
                    Spacer()
                    Chip(text: network.interface)
                }
                BigValue(value: download.number, unit: download.unit)
                Sparkline(values: monitor.networkHistory, tint: .accentBlue, filled: false).frame(height: 30)
                Spacer(minLength: 0)
                HStack {
                    CardFooter(text: "Upload \(Format.rate(network.upload))")
                    Spacer()
                    if let address = network.address {
                        Button(address) { SystemActions.copy(address) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryText)
                            .help("IPv4 address · click to copy")
                    }
                }
            }
        }
    }
}

struct FanCard: View {
    @EnvironmentObject private var fan: FanController

    var body: some View {
        let rpm = fan.fans.map(\.rpm).max() ?? 0
        let speed = fan.fans.map(\.speedFraction).max() ?? 0
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(symbol: "fan", title: "Fan")
                    Spacer()
                    if fan.hasFans { Chip(text: "Speed \(Format.percent(speed))%") }
                }
                if !fan.hasFans {
                    BigValue(value: "0", unit: "fans")
                    Spacer(minLength: 0)
                    CardFooter(text: "This Mac has no fans")
                } else if fan.isEnabled {
                    BigValue(value: "\(Int(rpm))", unit: "RPM")
                    HStack(spacing: 6) {
                        ForEach(FanMode.allCases) { mode in
                            Button(mode.title) { Task { await fan.select(mode) } }
                                .buttonStyle(PillButtonStyle(isSelected: fan.mode == mode))
                                .disabled(fan.isWorking)
                        }
                    }
                    Spacer(minLength: 0)
                    CardFooter(text: fan.message ?? fan.strategyText)
                } else {
                    BigValue(value: "\(Int(rpm))", unit: "RPM")
                    Button("Turn on fan control…") { fan.showsEnableSheet = true }
                        .buttonStyle(PillButtonStyle())
                    Spacer(minLength: 0)
                    CardFooter(text: "Off · Managed by macOS")
                }
            }
        }
        .sheet(isPresented: $fan.showsEnableSheet) { FanEnableSheet() }
    }
}
