import Darwin
import Foundation
import Testing

@testable import FanService
@testable import SMCKit

@Suite("SMC values")
struct SMCValueTests {
    @Test func encodesKeysAsFourCharacterCodes() throws {
        let key: SMCKey = "F0Ac"
        #expect(key.code == 0x4630_4163)
        #expect(key.description == "F0Ac")
        #expect(SMCKey(name: "toolong") == nil)
        #expect(SMCKey(name: "FNum") == "FNum")
        #expect(SMCKey.fan(1, "Mx")?.description == "F1Mx")
    }

    @Test func parameterBlockMatchesTheKernelLayout() {
        #expect(MemoryLayout<SMCParamStruct>.size == 80)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo) == 28)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data8) == 42)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.bytes) == 48)
    }

    @Test(arguments: [2317.0, 0.0, 6550.5])
    func roundTripsFloats(value: Double) throws {
        let template = SMCValue(type: "flt ", bytes: [0, 0, 0, 0])
        let bytes = try template.encoding(value)
        #expect(SMCValue(type: "flt ", bytes: bytes).double == value)
    }

    @Test func decodesFixedPointAndIntegers() throws {
        #expect(SMCValue(type: "fpe2", bytes: [0x24, 0x40]).double == 2320)
        #expect(SMCValue(type: "sp78", bytes: [0x2E, 0x80]).double == 46.5)
        #expect(SMCValue(type: "ui8 ", bytes: [3]).double == 3)
        #expect(SMCValue(type: "ui16", bytes: [0x01, 0x02]).double == 258)
        #expect(try SMCValue(type: "fpe2", bytes: [0, 0]).encoding(2320) == [0x24, 0x40])
        #expect(throws: SMCError.unsupportedType("ch8*")) { try SMCValue(type: "ch8*", bytes: []).encoding(1) }
    }

    @Test func averagesTemperatures() {
        #expect(ChipTemperatures.mean([40, 50, 60]) == 50)
        #expect(ChipTemperatures.mean([]) == nil)
    }
}

@Suite("Fan curve")
struct FanCurveTests {
    let curve = FanCurve(points: [
        .init(temperature: 50, fraction: 0.4), .init(temperature: 70, fraction: 0.6), .init(temperature: 90, fraction: 1),
    ])

    @Test func automaticLeavesFansToMacOS() {
        #expect(curve.fraction(for: .automatic, temperature: 99) == nil)
    }

    @Test func maximumIsFullSpeed() {
        #expect(curve.fraction(for: .maximum, temperature: 30) == 1)
    }

    @Test func interpolatesBetweenPointsAndIsFlatBeyondThem() {
        #expect(curve.fraction(at: 30) == 0.4)
        #expect(abs(curve.fraction(at: 60) - 0.5) < 0.0001)
        #expect(abs(curve.fraction(at: 80) - 0.8) < 0.0001)
        #expect(curve.fraction(at: 120) == 1)
        #expect(curve.fraction(for: .cool, temperature: nil) == 1)
    }

    @Test func quietHoursCapCoolButNotMax() {
        #expect(curve.fraction(for: .cool, temperature: 95, cap: 0.5) == 0.5)
        #expect(curve.fraction(for: .maximum, temperature: 95, cap: 0.5) == 1)
    }

    @Test func pointsStaySortedClampedAndApart() {
        let messy = FanCurve(points: [.init(temperature: 200, fraction: 3), .init(temperature: 10, fraction: -1)])
        #expect(messy.points.map(\.temperature) == [30, 100])
        #expect(messy.points.map(\.fraction) == [0, 1])
        // Dragging a point past its neighbor stops one degree short of it.
        let moved = curve.moving(0, to: .init(temperature: 85, fraction: 0.5))
        #expect(moved.points[0].temperature == 69)
        #expect(moved.points.map(\.temperature) == moved.points.map(\.temperature).sorted())
        #expect(FanCurve(points: []).points == FanCurve.standard.points)
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(curve)
        #expect(try JSONDecoder().decode(FanCurve.self, from: data) == curve)
    }

    @Test func strongestRunningAppRuleWins() {
        let rules = [
            AppFanRule(bundleIdentifier: "com.example.build", appName: "Build", mode: .cool),
            AppFanRule(bundleIdentifier: "com.example.render", appName: "Render", mode: .maximum),
        ]
        #expect(AppFanRule.strongest(rules, running: ["com.example.build"])?.appName == "Build")
        #expect(AppFanRule.strongest(rules, running: ["com.example.build", "com.example.render"])?.mode == .maximum)
        #expect(AppFanRule.strongest(rules, running: []) == nil)
        #expect(FanMode.automatic < .cool && FanMode.cool < .maximum)
    }

    @Test func fansWithoutASpeedRangeAreNotDriven() {
        let broken = FanReading(index: 0, rpm: 0, minimum: 0, maximum: 0, target: nil, mode: nil)
        #expect(!broken.isControllable)
        #expect(broken.rpm(atFraction: 1) == 0)
        let fan = FanReading(index: 0, rpm: 1200, minimum: 2317, maximum: 6550, target: nil, mode: 0)
        #expect(fan.isControllable)
        #expect(fan.rpm(atFraction: .nan) == 6550)
    }

    @Test func smallFirmwareRoundingStillCountsAsApplied() {
        #expect(FanControl.accepts(applied: 2320, requested: 2317))
        #expect(FanControl.accepts(applied: 6500, requested: 6550))
        #expect(!FanControl.accepts(applied: 2317, requested: 6550))
    }

    @Test func snapshotSurvivesARestart() throws {
        let snapshot = FanControlSnapshot(modes: [0: 3, 1: 0], unlock: 0)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(FanControlSnapshot.self, from: data) == snapshot)
    }

    @Test func fanPositionsStayWithinLimits() {
        let fan = FanReading(index: 0, rpm: 1200, minimum: 2317, maximum: 6550, target: nil, mode: 3)
        #expect(fan.rpm(atFraction: 0) == 2317)
        #expect(fan.rpm(atFraction: 1) == 6550)
        #expect(fan.rpm(atFraction: 7) == 6550)
        #expect(fan.rpm(atFraction: -1) == 2317)
        #expect(abs(fan.speedFraction - 1200.0 / 6550.0) < 0.0001)
    }
}

@Suite("Helper protocol")
struct HelperProtocolTests {
    @Test(arguments: [HelperRequest.status, .automatic, .manual(fraction: 0.55)])
    func requestsRoundTrip(request: HelperRequest) throws {
        let line = try HelperCodec.encode(request)
        #expect(line.last == UInt8(ascii: "\n"))
        #expect(try HelperCodec.decode(HelperRequest.self, from: line.dropLast()) == request)
    }

    @Test func rejectsUnknownRequests() {
        #expect(throws: (any Error).self) { try HelperCodec.decode(HelperRequest.self, from: Data(#"{"reboot":{}}"#.utf8)) }
    }

    @Test func installScriptQuotesPathsAndWritesAValidPlist() throws {
        let script = HelperInstallScript.install(helperSource: "/Apps/It's cfmac.app/helper", uid: 501)
        #expect(script.contains("'/Apps/It'\\''s cfmac.app/helper'"))
        #expect(script.contains("launchctl bootstrap system"))
        let plistData = Data(HelperInstallScript.launchdPlist(uid: 501).utf8)
        let plist = try #require(try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == HelperLayout.label)
        #expect(plist["ProgramArguments"] as? [String] == [HelperLayout.executablePath, "--allowed-uid", "501"])
        #expect(HelperInstallScript.uninstall().contains("bootout system/\(HelperLayout.label)"))
        #expect(HelperInstallScript.uninstall().contains(HelperLayout.statePath))
    }

    /// One request and response over a real Unix socket, framed by newlines.
    @Test func clientExchangesOneLineWithAServer() throws {
        let path = "/tmp/cfmac-test-\(getpid()).sock"
        unlink(path)
        defer { unlink(path) }
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try LineSocket.address(for: path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(bound == 0)
        try #require(listen(server, 1) == 0)
        let expected = HelperResponse(fans: [FanReading(index: 0, rpm: 0, minimum: 2317, maximum: 6550, target: nil, mode: 3)], manual: false)
        let serverThread = Thread {
            let client = LineSocket(descriptor: accept(server, nil, nil))
            guard let line = try? client.receiveLine(maxBytes: 1024),
                (try? HelperCodec.decode(HelperRequest.self, from: line)) == .status
            else { return }
            try? client.send(HelperCodec.encode(expected))
        }
        serverThread.start()
        let response = try HelperClient.send(.status, socketPath: path, timeout: 3)
        close(server)
        #expect(response == expected)
    }

    @Test func failsFastWhenNoHelperIsListening() {
        #expect(throws: LineSocketError.self) { try HelperClient.send(.status, socketPath: "/tmp/cfmac-missing.sock", timeout: 1) }
    }
}
