import Darwin
import FanService
import Foundation

/// Accepts one request per connection from a single allowed user.
final class SocketServer: @unchecked Sendable {
    private let path: String
    private let allowedUID: uid_t
    private let supervisor: FanSupervisor
    private var listener: Int32 = -1

    init(path: String, allowedUID: uid_t, supervisor: FanSupervisor) {
        self.path = path
        self.allowedUID = allowedUID
        self.supervisor = supervisor
    }

    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LineSocketError.system("socket", errno) }
        var address = try LineSocket.address(for: path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw LineSocketError.system("bind", errno) }
        // Only the allowed user (and root) may open the socket; the peer's user ID is
        // checked again on every connection.
        guard chown(path, allowedUID, 0) == 0, chmod(path, 0o600) == 0 else {
            close(fd)
            throw LineSocketError.system("chmod", errno)
        }
        guard listen(fd, 8) == 0 else { close(fd); throw LineSocketError.system("listen", errno) }
        listener = fd
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                log("accept failed: \(errno)")
                continue
            }
            serve(LineSocket(descriptor: client))
        }
    }

    private func serve(_ connection: consuming LineSocket) {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(connection.descriptor, &uid, &gid) == 0, uid == allowedUID || uid == 0 else {
            log("rejected connection from uid \(uid)")
            return
        }
        connection.disableSigPipe()
        do {
            try connection.setTimeout(3)
            let line = try connection.receiveLine(maxBytes: HelperLayout.maxMessageBytes)
            let response: HelperResponse
            if let request = try? HelperCodec.decode(HelperRequest.self, from: line) {
                response = supervisor.handle(request)
            } else {
                response = HelperResponse(fans: [], manual: false, error: "Unrecognized request")
            }
            try connection.send(HelperCodec.encode(response))
        } catch {
            log("connection error: \(error)")
        }
    }
}
