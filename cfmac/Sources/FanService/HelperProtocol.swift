import Foundation
import SMCKit

/// Installation layout of the privileged fan helper.
public enum HelperLayout {
    public static let label = "app.cfmac.helper"
    public static let executablePath = "/Library/PrivilegedHelperTools/\(label)"
    public static let launchdPlistPath = "/Library/LaunchDaemons/\(label).plist"
    public static let socketPath = "/var/run/\(label).sock"
    /// Bumped whenever the request or response format changes.
    public static let protocolVersion = 1
    /// Manual fan control ends automatically unless the app renews it within this window.
    public static let leaseSeconds: TimeInterval = 20
    /// Largest request or response line accepted on the socket.
    public static let maxMessageBytes = 16 * 1024
}

/// A request from the app to the helper. One request per connection.
public enum HelperRequest: Codable, Sendable, Equatable {
    /// Report helper version and fan state.
    case status
    /// Run every fan at `fraction` between its minimum (0) and maximum (1) RPM, renewing the lease.
    case manual(fraction: Double)
    /// Give fans back to macOS.
    case automatic
}

public struct HelperResponse: Codable, Sendable, Equatable {
    public var version: Int
    public var fans: [FanReading]
    /// True while the helper holds manual control.
    public var manual: Bool
    public var error: String?

    public init(version: Int = HelperLayout.protocolVersion, fans: [FanReading], manual: Bool, error: String? = nil) {
        self.version = version
        self.fans = fans
        self.manual = manual
        self.error = error
    }
}

public enum HelperCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}
