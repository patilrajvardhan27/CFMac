import Foundation

public struct ShellResult: Sendable, Equatable {
    public let status: Int32
    public let output: String
    public let error: String

    public init(status: Int32, output: String, error: String) {
        self.status = status
        self.output = output
        self.error = error
    }

    public var succeeded: Bool { status == 0 }
    /// osascript reports error -128 when the user cancels an authorization prompt.
    public var wasCancelledByUser: Bool { error.contains("-128") }
}

/// Runs external tools without a shell, so arguments are never re-parsed.
public enum Shell {
    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    public static let homebrew = firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
    public static let appStoreCLI = firstExecutable(["/opt/homebrew/bin/mas", "/usr/local/bin/mas"])

    public static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `executable` and waits for it to exit, terminating it after `timeout` seconds.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 60) -> ShellResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return ShellResult(status: 127, output: "", error: "\(executable) not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        // Drain both pipes concurrently so a chatty child never blocks on a full pipe.
        let output = PipeReader(stdout.fileHandleForReading)
        let error = PipeReader(stderr.fileHandleForReading)
        do {
            try process.run()
        } catch {
            return ShellResult(status: 126, output: "", error: error.localizedDescription)
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        return ShellResult(status: process.terminationStatus, output: output.text(), error: error.text())
    }

    /// Runs `script` with /bin/sh as root after the standard macOS administrator prompt.
    /// The script goes to a new file in the user's private temporary folder, created
    /// exclusively with owner-only permissions so nothing can swap or read it, and is
    /// deleted afterwards.
    public static func runAsAdministrator(script: String, prompt: String) -> ShellResult {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("cfmac-\(UUID().uuidString).sh").path
        guard writePrivateFile(path, contents: Data(script.utf8)) else {
            return ShellResult(status: 1, output: "", error: "Could not prepare the administrator task")
        }
        defer { unlink(path) }
        let command =
            "do shell script \"/bin/sh \" & quoted form of \(appleScriptLiteral(path)) "
            + "with prompt \(appleScriptLiteral(prompt)) with administrator privileges"
        return run("/usr/bin/osascript", ["-e", command], timeout: 900)
    }

    /// Creates `path` (failing if anything already exists there, including a symlink),
    /// readable and writable by the owner only.
    static func writePrivateFile(_ path: String, contents: Data) -> Bool {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return contents.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            return write(descriptor, base, raw.count) == raw.count
        }
    }

    /// Quotes `text` as an AppleScript string literal.
    public static func appleScriptLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Reads a pipe to its end on a background queue.
private final class PipeReader: @unchecked Sendable {
    private var data = Data()
    private let finished = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [self] in
            data = handle.readDataToEndOfFile()
            finished.signal()
        }
    }

    /// Waits briefly for the pipe to close; a lingering grandchild cannot hang the caller.
    func text() -> String {
        guard finished.wait(timeout: .now() + 5) == .success else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
