import Foundation
import Testing

@testable import CfmacCore

@Suite("Parsers")
struct ParsingTests {
    @Test func parsesHomebrewOutdated() throws {
        let json = """
            {"formulae":[{"name":"git","installed_versions":["2.44.0"],"current_version":"2.45.1"}],
             "casks":[{"name":"firefox","installed_versions":["125.0"],"current_version":"126.0"}]}
            """
        let updates = try #require(Updates.parseHomebrew(json))
        #expect(updates.map(\.name) == ["git", "firefox"])
        #expect(updates.map(\.source) == [.formula, .cask])
        #expect(updates[0].installedVersion == "2.44.0")
        #expect(updates[0].latestVersion == "2.45.1")
        #expect(Updates.parseHomebrew("not json") == nil)
    }

    @Test func parsesAppStoreOutdated() {
        let output = "497799835 Xcode (15.0 -> 15.1)\n409183694 Keynote (13.1 -> 14.0)\ngarbage line\n"
        let updates = Updates.parseAppStore(output)
        #expect(updates.map(\.name) == ["Xcode", "Keynote"])
        #expect(updates[0].appStoreIdentifier == "497799835")
        #expect(updates[1].installedVersion == "13.1")
        #expect(updates[1].latestVersion == "14.0")
    }

    @Test func parsesProcessList() {
        let output = "  101  12.5  2048 alice /Applications/Example.app/Contents/MacOS/Example\n    1   0.0   512 root /sbin/launchd\nbad\n"
        let rows = ProcessList.parse(output)
        #expect(rows.count == 2)
        #expect(rows[0].pid == 101)
        #expect(rows[0].cpu == 12.5)
        #expect(rows[0].memory == 2048 * 1024)
        #expect(rows[0].name == "Example")
        #expect(rows[0].appPath == "/Applications/Example.app")
        #expect(rows[1].appPath == nil)
    }

    @Test func parsesBatteryMaximumCapacity() {
        let json = #"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"96%"}}]}"#
        #expect(BatteryMeter.parseMaximumCapacity(json) == 96)
        #expect(BatteryMeter.parseMaximumCapacity("{}") == nil)
    }

    @Test func buildsOneAdministratorScript() {
        let tasks = OptimizeCatalog.tasks(protected: []).filter(\.needsAdministrator)
        let script = OptimizeCatalog.administratorScript(for: tasks)
        for task in tasks { #expect(script.contains("echo \"\(task.id)=0\"")) }
        #expect(OptimizeCatalog.administratorResults("dns=0\npurge=1\nnoise\n") == ["dns": true, "purge": false])
    }

    @Test func parsesMarkdownBlocks() {
        let markdown = """
            # Title

            First line
            continues here.

            - item one
              wraps here
            - item two

            ```
            code  block
            ```
            ---
            """
        #expect(
            MarkdownBlocks.parse(markdown) == [
                .heading(level: 1, text: "Title"),
                .paragraph("First line continues here."),
                .bullet("item one wraps here"),
                .bullet("item two"),
                .preformatted("code  block"),
                .rule,
            ])
    }
}

@Suite("Health and formatting")
struct HealthAndFormatTests {
    static let healthy = HealthScore.Inputs(
        cpu: 0.1, pressure: .normal, freeDiskFraction: 0.5, batteryHealth: 98,
        batteryCycles: 100, thermalState: .nominal, uptime: 3_600)

    @Test func healthyMacScoresFull() {
        let score = HealthScore(Self.healthy)
        #expect(score.score == 100)
        #expect(score.label == "Excellent")
        #expect(score.headline == "Current readings normal")
    }

    @Test func penaltiesAddUp() {
        var inputs = Self.healthy
        inputs.cpu = 0.9
        inputs.pressure = .critical
        inputs.freeDiskFraction = 0.05
        let score = HealthScore(inputs)
        #expect(score.score == 100 - 15 - 25 - 20)
        #expect(score.label == "Needs Attention")
        #expect(score.headline == "Memory pressure")
    }

    @Test func worstCaseAppliesEveryPenalty() {
        let inputs = HealthScore.Inputs(
            cpu: 1, pressure: .critical, freeDiskFraction: 0, batteryHealth: 50, batteryCycles: 2000,
            thermalState: .critical, uptime: 60 * 86_400)
        let score = HealthScore(inputs)
        #expect(score.penalties.count == 7)
        #expect(score.score == 5)
        #expect(score.label == "Needs Attention")
    }

    @Test func formatsNumbers() {
        #expect(Format.rate(10) == "<1 KB/s")
        #expect(Format.rateParts(.nan) == ("0", "KB/s"))
        #expect(Format.percent(1.4) == 100)
        #expect(Format.percent(-1) == 0)
        let parts = Format.bytesParts(165_000_000_000)
        #expect(parts.unit == "GB")
        #expect(!parts.number.isEmpty)
    }

    @Test func quotesForAppleScript() {
        #expect(Shell.appleScriptLiteral("say \"hi\" \\") == "\"say \\\"hi\\\" \\\\\"")
    }

    @Test func runsCommandsAndReportsFailures() {
        #expect(Shell.run("/bin/echo", ["hello"]).output == "hello\n")
        #expect(Shell.run("/usr/bin/false").status == 1)
        #expect(Shell.run("/nonexistent/tool").status == 127)
        #expect(Shell.run("/bin/sleep", ["5"], timeout: 0.3).status != 0)
    }
}
