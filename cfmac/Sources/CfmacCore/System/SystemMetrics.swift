import Darwin
import Foundation
import IOKit
import IOKit.ps
import os

// MARK: - CPU

/// Per-core utilization from tick deltas between successive samples.
public struct CPUMeter: Sendable {
    private var previous: [[UInt32]] = []

    public init() {}

    /// Returns 0...1 per core. The first call establishes a baseline and returns zeros.
    public mutating func sample() -> [Double] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
            let info
        else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        let ticks = (0..<Int(count)).map { core in
            (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
        }
        defer { previous = ticks }
        guard previous.count == ticks.count else { return ticks.map { _ in 0 } }
        return zip(ticks, previous).map { now, before in
            let deltas = (0..<states).map { Double(now[$0] &- before[$0]) }
            let total = deltas.reduce(0, +)
            return total > 0 ? (total - deltas[Int(CPU_STATE_IDLE)]) / total : 0
        }
    }

    public static func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : 0
    }
}

// MARK: - Memory

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    public static func current() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }
}

public struct MemoryReading: Sendable, Equatable {
    public let used: Int64
    public let total: Int64
    public let swapUsed: Int64

    public init(used: Int64, total: Int64, swapUsed: Int64) {
        self.used = used
        self.total = total
        self.swapUsed = swapUsed
    }

    public var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// App, wired and compressed memory, matching Activity Monitor's "Memory Used".
    public static func current() -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var used: Int64 = 0
        if status == KERN_SUCCESS {
            let appPages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            used = (appPages + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * Int64(pageSize)
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        return MemoryReading(used: used, total: Int64(ProcessInfo.processInfo.physicalMemory), swapUsed: Int64(swap.xsu_used))
    }
}

// MARK: - GPU

public enum GPUMeter {
    /// Busiest accelerator's utilization (0...1) from IOAccelerator performance statistics.
    public static func utilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let stats =
                IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            if let percent = stats?["Device Utilization %"] as? Int {
                busiest = max(busiest ?? 0, Double(percent) / 100)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return busiest
    }
}

// MARK: - Battery

public struct BatteryReading: Sendable, Equatable {
    public var percent: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    /// Maximum capacity as shown in System Settings, in percent.
    public var health: Int?
    public var cycles: Int?
    public var temperature: Double?
    public var adapterWatts: Int?
    public var minutesRemaining: Int?
    public var condition: String?

    public var statusText: String {
        if isCharging, let minutes = minutesRemaining { return "Full in \(Format.duration(Double(minutes) * 60))" }
        if isPluggedIn { return isCharging ? "Charging" : (percent >= 99 ? "Charged" : "Plugged in, not charging") }
        if let minutes = minutesRemaining { return "\(Format.duration(Double(minutes) * 60)) left" }
        return "On battery"
    }
}

public enum BatteryMeter {
    private static let capacityCache = OSAllocatedUnfairLock<(value: Int?, read: Date)?>(initialState: nil)
    private static let capacityCacheLifetime: TimeInterval = 600

    public static func current() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = (charging ? description[kIOPSTimeToFullChargeKey] : description[kIOPSTimeToEmptyKey]) as? Int
            var reading = BatteryReading(
                percent: description[kIOPSCurrentCapacityKey] as? Int ?? 0,
                isCharging: charging,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesRemaining: (minutes ?? 0) > 0 ? minutes : nil,
                condition: description["BatteryHealthCondition"] as? String
            )
            addRegistryFacts(to: &reading)
            return reading
        }
        return nil
    }

    private static func addRegistryFacts(to reading: inout BatteryReading) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        func top(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        // Newer macOS versions nest capacity facts inside "BatteryData".
        let nested = top("BatteryData") as? [String: Any] ?? [:]
        func value(_ key: String) -> Any? { top(key) ?? nested[key] }
        reading.cycles = value("CycleCount") as? Int
        if let temperature = value("Temperature") as? Int, temperature > 0 { reading.temperature = Double(temperature) / 100 }
        if let adapter = top("AdapterDetails") as? [String: Any] { reading.adapterWatts = adapter["Watts"] as? Int }
        if let percent = maximumCapacityPercent() {
            reading.health = percent
        } else if let design = value("DesignCapacity") as? Int, design > 0,
            let capacity = (value("NominalChargeCapacity") as? Int) ?? (value("AppleRawMaxCapacity") as? Int)
        {
            reading.health = min(100, Int((Double(capacity) / Double(design) * 100).rounded()))
        }
    }

    /// The "Maximum Capacity" macOS shows. macOS computes it rather than storing it in the
    /// registry, so it is read from system_profiler and cached for ten minutes.
    static func maximumCapacityPercent() -> Int? {
        if let cached = capacityCache.withLock({ $0 }), Date().timeIntervalSince(cached.read) < capacityCacheLifetime {
            return cached.value
        }
        let output = Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"], timeout: 15).output
        let value = parseMaximumCapacity(output)
        capacityCache.withLock { $0 = (value, Date()) }
        return value
    }

    static func parseMaximumCapacity(_ json: String) -> Int? {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["SPPowerDataType"] as? [[String: Any]]
        else { return nil }
        for item in items {
            if let health = item["sppower_battery_health_info"] as? [String: Any],
                let text = health["sppower_battery_health_maximum_capacity"] as? String
            {
                return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
            }
        }
        return nil
    }
}

// MARK: - Network

public struct NetworkReading: Sendable, Equatable {
    public var download: Double = 0
    public var upload: Double = 0
    public var interface = "Offline"
    public var address: String?

    public init(download: Double = 0, upload: Double = 0, interface: String = "Offline", address: String? = nil) {
        self.download = download
        self.upload = upload
        self.interface = interface
        self.address = address
    }
}

/// Byte-counter deltas across samples of the en* interfaces.
public struct NetworkMeter: Sendable {
    private var previous: (received: UInt64, sent: UInt64, time: Date)?

    public init() {}

    public mutating func sample(now: Date = Date()) -> NetworkReading {
        let counters = Self.counters()
        var reading = NetworkReading(interface: counters.interface, address: counters.address)
        if let previous {
            let elapsed = max(0.5, now.timeIntervalSince(previous.time))
            reading.download = Double(counters.received &- previous.received) / elapsed
            reading.upload = Double(counters.sent &- previous.sent) / elapsed
        }
        previous = (counters.received, counters.sent, now)
        return reading
    }

    static func counters() -> (received: UInt64, sent: UInt64, interface: String, address: String?) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var address: String?
        var active: Set<String> = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0, "Offline", nil) }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            guard name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let socketAddress = entry.ifa_addr else { continue }
            switch Int32(socketAddress.pointee.sa_family) {
            case AF_LINK:
                if let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    received += UInt64(data.ifi_ibytes)
                    sent += UInt64(data.ifi_obytes)
                }
            case AF_INET:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = address ?? String(nulTerminated: host)
                }
                active.insert(name)
            default:
                break
            }
        }
        let interface = active.contains("en0") ? "Wi-Fi" : active.isEmpty ? "Offline" : "Ethernet"
        return (received, sent, interface, address)
    }
}

// MARK: - Processes

public struct ProcessRow: Identifiable, Hashable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let path: String
    public let user: String
    public let cpu: Double
    public let memory: Int64

    /// The enclosing .app bundle, used for icons.
    public var appPath: String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

public enum ProcessList {
    public static func current() -> [ProcessRow] {
        parse(Shell.run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,user=,comm="], timeout: 5).output)
    }

    static func parse(_ output: String) -> [ProcessRow] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5, let pid = Int32(fields[0]), let cpu = Double(fields[1]), let rss = Int64(fields[2]) else { return nil }
            let path = String(fields[4])
            return ProcessRow(pid: pid, name: (path as NSString).lastPathComponent, path: path, user: String(fields[3]), cpu: cpu, memory: rss * 1024)
        }
    }

    public enum SignalResult: Equatable, Sendable {
        case sent, protectedProcess, changed, permissionDenied, gone
    }

    /// Signals `process` after confirming its PID still runs the same executable.
    public static func signal(_ process: ProcessRow, force: Bool) -> SignalResult {
        guard process.pid > 1 else { return .protectedProcess }
        guard let current = current().first(where: { $0.pid == process.pid }) else { return .gone }
        guard current.path == process.path else { return .changed }
        if kill(process.pid, force ? SIGKILL : SIGTERM) == 0 { return .sent }
        return errno == EPERM ? .permissionDenied : .gone
    }
}

// MARK: - Machine facts

public enum MachineInfo {
    public static let chipName: String = {
        sysctlString("machdep.cpu.brand_string")?.replacingOccurrences(of: "Apple ", with: "") ?? "Mac"
    }()

    public static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }()

    public static func uptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        return String(nulTerminated: buffer)
    }
}

// MARK: - Disk

public struct VolumeReading: Sendable, Equatable {
    public let total: Int64
    public let available: Int64

    public init(total: Int64, available: Int64) {
        self.total = total
        self.available = available
    }

    public var used: Int64 { max(0, total - available) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Startup volume. "Available" includes space macOS can free on demand, as in System Settings.
    public static func startup() -> VolumeReading {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return VolumeReading(total: Int64(values?.volumeTotalCapacity ?? 0), available: values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

extension String {
    /// Decodes a C character buffer up to its first NUL.
    init(nulTerminated buffer: [CChar]) {
        self.init(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
