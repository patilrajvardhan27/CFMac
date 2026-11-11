// cfmac-helper: a root LaunchDaemon that changes fan speed on request from cfmac.
// It controls nothing else. Manual control is leased and ends automatically.
import Darwin
import FanService
import Foundation
import SMCKit

guard geteuid() == 0 else {
    log("must run as root")
    exit(EX_NOPERM)
}

let arguments = CommandLine.arguments
guard let flag = arguments.firstIndex(of: "--allowed-uid"), flag + 1 < arguments.count,
    let allowedUID = uid_t(arguments[flag + 1])
else {
    log("usage: cfmac-helper --allowed-uid <uid>")
    exit(EX_USAGE)
}

let smc: SMCConnection
do {
    smc = try SMCConnection()
} catch {
    log("cannot open the SMC: \(error)")
    exit(EX_UNAVAILABLE)
}

let supervisor = FanSupervisor(smc: smc)
supervisor.startWatchdog()

let server = SocketServer(path: HelperLayout.socketPath, allowedUID: allowedUID, supervisor: supervisor)
do {
    try server.start()
} catch {
    log("cannot listen on \(HelperLayout.socketPath): \(error)")
    exit(EX_OSERR)
}

// Return fans to macOS before launchd stops or unloads the helper.
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        supervisor.restoreAll()
        unlink(HelperLayout.socketPath)
        exit(EXIT_SUCCESS)
    }
    source.resume()
    signalSources.append(source)
}

log("ready (protocol \(HelperLayout.protocolVersion))")
dispatchMain()
