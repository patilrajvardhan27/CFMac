import CfmacCore
import Foundation

/// One snapshot of live readings.
struct SystemSnapshot {
    var cpuCores: [Double] = []
    var loadAverage: Double = 0
    var gpu: Double?
    var memory = MemoryReading(used: 0, total: Int64(ProcessInfo.processInfo.physicalMemory), swapUsed: 0)
    var pressure = MemoryPressure.normal
    var volume = VolumeReading(total: 0, available: 0)
    var network = NetworkReading()
    var battery: BatteryReading?
    var uptime: TimeInterval = 0
    var thermalState = ProcessInfo.ThermalState.nominal
    var processes: [ProcessRow] = []

    var cpu: Double { cpuCores.isEmpty ? 0 : cpuCores.reduce(0, +) / Double(cpuCores.count) }
}

/// The single owner of live metrics. Samples every two seconds while any view needs it.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    static let interval: TimeInterval = 2
    private static let historyLength = 60

    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var networkHistory: [Double] = []

    private var cpuMeter = CPUMeter()
    private var networkMeter = NetworkMeter()
    private var timer: Timer?
    private var consumers = 0
    private var ticks = 0
    private var lowDiskAlerted = false
    private var processRefresh: Task<Void, Never>?

    var health: HealthScore {
        HealthScore(
            .init(
                cpu: snapshot.cpu, pressure: snapshot.pressure,
                freeDiskFraction: snapshot.volume.total > 0 ? Double(snapshot.volume.available) / Double(snapshot.volume.total) : nil,
                batteryHealth: snapshot.battery?.health, batteryCycles: snapshot.battery?.cycles,
                thermalState: snapshot.thermalState, uptime: snapshot.uptime
            ))
    }

    /// Starts sampling for one more consumer. Balance with `release()`.
    func retain() {
        consumers += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func release() {
        consumers = max(0, consumers - 1)
        guard consumers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        ticks += 1
        var next = snapshot
        next.cpuCores = cpuMeter.sample()
        next.loadAverage = CPUMeter.loadAverage()
        next.gpu = GPUMeter.utilization()
        next.memory = MemoryReading.current()
        next.pressure = MemoryPressure.current()
        next.volume = VolumeReading.startup()
        next.network = networkMeter.sample()
        next.uptime = MachineInfo.uptime()
        next.thermalState = ProcessInfo.processInfo.thermalState
        snapshot = next
        append(&cpuHistory, next.cpu)
        append(&memoryHistory, next.memory.fraction)
        append(&gpuHistory, next.gpu ?? 0)
        append(&networkHistory, min(1, next.network.download / 5_000_000))
        alertIfDiskLow(next.volume)
        refreshSlowReadings(includeBattery: ticks % 5 == 1)
    }

    /// Process list and battery shell out, so they run off the main actor.
    private func refreshSlowReadings(includeBattery: Bool) {
        guard processRefresh == nil else { return }
        processRefresh = Task { [weak self] in
            let (processes, battery) = await Task.detached(priority: .utility) {
                (ProcessList.current().sorted { $0.memory > $1.memory }, includeBattery ? BatteryMeter.current() : nil)
            }.value
            guard let self else { return }
            snapshot.processes = processes
            if includeBattery { snapshot.battery = battery }
            processRefresh = nil
        }
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    private func alertIfDiskLow(_ volume: VolumeReading) {
        guard AppSettings.shared.lowDiskAlert, volume.total > 0 else { return }
        let low = Double(volume.available) / Double(volume.total) < 0.1 && volume.available < 30_000_000_000
        if low, !lowDiskAlerted {
            lowDiskAlerted = true
            Notifier.post(
                title: "Low disk space", body: "Only \(Format.bytes(volume.available)) is available on the startup disk. Open Clean to free up space.")
        } else if !low {
            lowDiskAlerted = false
        }
    }
}
