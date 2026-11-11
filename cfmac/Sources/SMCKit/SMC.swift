import Foundation
import IOKit

/// A four-character SMC key such as `FNum` or `F0Ac`.
public struct SMCKey: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let code: UInt32

    /// Literal keys (`"FNum"`) must be exactly four ASCII characters.
    public init(stringLiteral text: String) {
        guard let key = SMCKey(name: text) else {
            preconditionFailure("SMC key \"\(text)\" must be four ASCII characters")
        }
        self = key
    }

    /// Fails unless `name` is exactly four ASCII characters.
    public init?(name text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count == 4 else { return nil }
        code = bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    init(code: UInt32) { self.code = code }

    public var description: String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self)
    }

    /// Per-fan keys, e.g. `fan(0, "Ac")` → `F0Ac`.
    public static func fan(_ index: Int, _ suffix: String) -> SMCKey? { SMCKey(name: "F\(index)\(suffix)") }
}

public enum SMCError: Error, Equatable, Sendable {
    case serviceUnavailable
    case openFailed(kern_return_t)
    case keyNotFound(String)
    case callFailed(kern_return_t)
    case notPrivileged
    case unsupportedType(String)
    case sizeMismatch
}

/// A raw SMC value with its declared type, decoded on demand.
public struct SMCValue: Sendable, Equatable {
    public let type: String
    public let bytes: [UInt8]

    public init(type: String, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }

    /// Numeric reading for the types fans and sensors use.
    public var double: Double? {
        switch type {
        case "flt ":
            guard bytes.count == 4 else { return nil }
            return Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24))
        case "fpe2":
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            guard bytes.count == 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count == 4 else { return nil }
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }

    /// Encodes `number` in this value's type, keeping the declared size.
    public func encoding(_ number: Double) throws -> [UInt8] {
        switch type {
        case "flt ":
            let bits = Float(number).bitPattern
            return [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> $0) }
        case "fpe2":
            let raw = UInt16(clamping: Int((number * 4).rounded()))
            return [UInt8(raw >> 8), UInt8(truncatingIfNeeded: raw)]
        case "ui8 ":
            return [UInt8(clamping: Int(number.rounded()))]
        case "ui16":
            let raw = UInt16(clamping: Int(number.rounded()))
            return [UInt8(raw >> 8), UInt8(truncatingIfNeeded: raw)]
        default:
            throw SMCError.unsupportedType(type)
        }
    }
}

/// Parameter block exchanged with the AppleSMC user client (selector 2).
/// Field order and padding reproduce the 80-byte C layout the kernel expects.
struct SMCParamStruct {
    struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    struct PowerLimits { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }

    var key: UInt32 = 0
    var version = Version()
    var powerLimits = PowerLimits()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)

    enum Command: UInt8 {
        case readBytes = 5
        case writeBytes = 6
        case readIndex = 8
        case readKeyInfo = 9
    }

    var payload: [UInt8] {
        get { withUnsafeBytes(of: bytes) { Array($0) } }
        set {
            withUnsafeMutableBytes(of: &bytes) { raw in
                raw.initializeMemory(as: UInt8.self, repeating: 0)
                for (i, b) in newValue.prefix(32).enumerated() { raw[i] = b }
            }
        }
    }
}

/// One open connection to the AppleSMC driver. Reads work as any user; writes need root.
public final class SMCConnection: @unchecked Sendable {
    private let connection: io_connect_t
    private let lock = NSLock()

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceUnavailable }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
        connection = conn
    }

    deinit { IOServiceClose(connection) }

    public func read(_ key: SMCKey) throws -> SMCValue {
        lock.lock()
        defer { lock.unlock() }
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCParamStruct.Command.readBytes.rawValue
        let output = try call(input)
        let size = Int(min(info.dataSize, 32))
        return SMCValue(type: SMCKey(code: info.dataType).description, bytes: Array(output.payload.prefix(size)))
    }

    public func write(_ key: SMCKey, bytes: [UInt8]) throws {
        lock.lock()
        defer { lock.unlock() }
        let info = try keyInfo(key)
        guard Int(info.dataSize) == bytes.count else { throw SMCError.sizeMismatch }
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCParamStruct.Command.writeBytes.rawValue
        input.payload = bytes
        _ = try call(input)
    }

    /// Writes a number using the key's own type.
    public func write(_ key: SMCKey, number: Double) throws {
        let current = try read(key)
        try write(key, bytes: current.encoding(number))
    }

    public func double(_ key: SMCKey) -> Double? { try? read(key).double }

    /// Every key the SMC exposes, in firmware order.
    public func allKeys() -> [SMCKey] {
        guard let count = double("#KEY").map(Int.init) else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return (0..<count).compactMap { index in
            var input = SMCParamStruct()
            input.data8 = SMCParamStruct.Command.readIndex.rawValue
            input.data32 = UInt32(index)
            return (try? call(input)).map { SMCKey(code: $0.key) }
        }
    }

    private func keyInfo(_ key: SMCKey) throws -> SMCParamStruct.KeyInfo {
        var input = SMCParamStruct()
        input.key = key.code
        input.data8 = SMCParamStruct.Command.readKeyInfo.rawValue
        let output = try call(input)
        guard output.keyInfo.dataSize > 0 else { throw SMCError.keyNotFound(key.description) }
        return output.keyInfo
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &size)
        if kr == kIOReturnNotPrivileged { throw SMCError.notPrivileged }
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }
        // result 132 (0x84) is the SMC's "key not found".
        if output.result == 132 { throw SMCError.keyNotFound(SMCKey(code: input.key).description) }
        guard output.result == 0 else { throw SMCError.callFailed(kern_return_t(output.result)) }
        return output
    }
}
