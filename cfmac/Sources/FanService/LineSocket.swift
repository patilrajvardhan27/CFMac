import Darwin
import Foundation

public enum LineSocketError: Error, Equatable, Sendable {
    case pathTooLong
    case system(String, Int32)
    case closed
    case messageTooLarge
}

/// Newline-framed messages over a Unix domain socket, with send/receive timeouts.
public struct LineSocket: ~Copyable {
    public let descriptor: Int32

    public init(descriptor: Int32) { self.descriptor = descriptor }

    deinit { close(descriptor) }

    /// Connects to `path`, failing if no server answers.
    public static func connect(to path: String, timeout: TimeInterval) throws -> LineSocket {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LineSocketError.system("socket", errno) }
        let socket = LineSocket(descriptor: fd)
        socket.disableSigPipe()
        try socket.setTimeout(timeout)
        var address = try Self.address(for: path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw LineSocketError.system("connect", errno) }
        return socket
    }

    /// Writes to a peer that has gone away fail with EPIPE instead of raising SIGPIPE.
    public func disableSigPipe() {
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    public func setTimeout(_ seconds: TimeInterval) throws {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            guard setsockopt(descriptor, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
                throw LineSocketError.system("setsockopt", errno)
            }
        }
    }

    public func send(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, base + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw LineSocketError.system("write", errno)
                }
                offset += written
            }
        }
    }

    /// Reads up to and excluding the first newline.
    public func receiveLine(maxBytes: Int) throws -> Data {
        var line = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw LineSocketError.system("read", errno)
            }
            if count == 0 { throw LineSocketError.closed }
            if let newline = buffer[0..<count].firstIndex(of: UInt8(ascii: "\n")) {
                line.append(contentsOf: buffer[0..<newline])
                return line
            }
            line.append(contentsOf: buffer[0..<count])
            if line.count > maxBytes { throw LineSocketError.messageTooLarge }
        }
    }

    public static func address(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw LineSocketError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}

/// Sends one request to the helper and returns its response.
public enum HelperClient {
    public static func send(_ request: HelperRequest, socketPath: String = HelperLayout.socketPath, timeout: TimeInterval = 8) throws -> HelperResponse {
        let socket = try LineSocket.connect(to: socketPath, timeout: timeout)
        try socket.send(HelperCodec.encode(request))
        let line = try socket.receiveLine(maxBytes: HelperLayout.maxMessageBytes)
        return try HelperCodec.decode(HelperResponse.self, from: line)
    }
}
