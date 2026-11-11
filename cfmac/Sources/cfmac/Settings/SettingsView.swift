import AppKit
import Artwork
import CfmacCore
import FanService
import SoundKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            SoundSettings().tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            CleaningSettings().tabItem { Label("Cleaning", systemImage: "sparkles") }
            FanSettings().tabItem { Label("Fan", systemImage: "fan") }
            WatchlistSettings().tabItem { Label("Watchlist", systemImage: "eye") }
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "command") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 680, height: 560)
    }
}

struct Described: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Edits minutes-after-midnight with a time picker.
private struct MinutesPicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes * 60)) },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
            ), displayedComponents: .hourAndMinute)
    }
}

private struct QuietHoursEditor: View {
    @Binding var hours: QuietHours
    let detail: String

    var body: some View {
        Toggle(isOn: $hours.isEnabled) { Described(title: "Quiet hours", detail: detail) }
        if hours.isEnabled {
            HStack {
                MinutesPicker(title: "From", minutes: $hours.start)
                MinutesPicker(title: "to", minutes: $hours.end)
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("App Preferences") {
                Toggle(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })) {
                    Described(title: "Launch at login", detail: "Menu bar tools are ready when you reach the desktop")
                }
                Toggle(isOn: $settings.removeAppData) {
                    Described(title: "Remove data and settings with apps", detail: "Strong matches are selected; others need review")
                }
                Toggle(isOn: $settings.lowDiskAlert) {
                    Described(title: "Low disk space alert", detail: "One alert when free space is below both 10% and 30 GB")
                }
            }
            Section("Screen") {
                Picker("Keep Screen On mode", selection: $settings.keepAwakeMode) {
                    ForEach(KeepAwakeMode.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.keepAwakeMode.detail).font(.caption).foregroundStyle(.secondary)
                Picker("Clean Screen duration", selection: $settings.cleanScreenSeconds) {
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("Exit manually").tag(0)
                }
            }
            Section("About") {
                HStack {
                    Described(title: "\(AppInfo.name) \(AppInfo.version)", detail: AppInfo.copyright)
                    Spacer()
                    Button("Terms") { openWindow(id: WindowID.legal, value: LegalDocument.terms) }
                    Button("Licenses") { openWindow(id: WindowID.legal, value: LegalDocument.notices) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @Local private var customizingStatus = false

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $settings.useSystemAccent) {
                    Described(title: "Use the macOS accent color", detail: "Links and highlights follow System Settings › Appearance")
                }
            }
            Section("Tab colors") {
                ForEach(AppTab.allCases) { tab in
                    HStack {
                        ColorPicker(tab.title, selection: tintBinding(tab), supportsOpacity: false)
                        if settings.tabTints[tab.rawValue] != nil {
                            Button("Reset") { settings.tabTints[tab.rawValue] = nil }.buttonStyle(.link)
                        }
                    }
                }
            }
            Section("Planets") {
                ForEach(HeroSlot.allCases) { slot in
                    Picker(slot.title, selection: Binding(get: { settings.planet(for: slot) }, set: { settings.heroPlanets[slot] = $0 })) {
                        ForEach(Planet.allCases) { Text($0.title).tag($0) }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Spin speed: \(String(format: "%.2g", settings.planetSpeed))×")
                    Slider(value: $settings.planetSpeed, in: 0.25...3)
                }
                Toggle(isOn: $settings.reduceMotion) {
                    Described(
                        title: "Reduce motion",
                        detail: "Planets hold still and animations stop. Also follows the macOS Reduce Motion setting, and uses less energy")
                }
            }
            Section("Status") {
                Button("Arrange Status Cards…") { customizingStatus = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $customizingStatus) { StatusCustomizeSheet().environmentObject(settings) }
    }

    private func tintBinding(_ tab: AppTab) -> Binding<Color> {
        Binding(
            get: { Color(hex: settings.tabTints[tab.rawValue] ?? tab.defaultTint) },
            set: { settings.tabTints[tab.rawValue] = NSColor($0).hexValue }
        )
    }
}

// MARK: - Menu bar

private struct MenuBarSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show cfmac in the menu bar", isOn: $settings.showMenuBar)
                Picker("Menu bar content", selection: $settings.menuBarContent) {
                    ForEach(MenuBarContent.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Runner") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(Runner.allCases) { runner in
                        RunnerTile(runner: runner, isSelected: settings.runner == runner) { settings.runner = runner }
                    }
                }
                Picker("Runs faster with", selection: $settings.runnerSpeedSource) {
                    ForEach(RunnerSpeedSource.allCases) { Text($0.title).tag($0) }
                }
            }
            .disabled(settings.menuBarContent == .metric)
            Section("Live numbers (up to three)") {
                ForEach(0..<3, id: \.self) { slot in
                    Picker("Slot \(slot + 1)", selection: metricBinding(slot)) {
                        Text("None").tag(MenuBarMetric?.none)
                        ForEach(MenuBarMetric.allCases) { Text($0.title).tag(MenuBarMetric?.some($0)) }
                    }
                }
            }
            .disabled(settings.menuBarContent == .runner)
        }
        .formStyle(.grouped)
    }

    private func metricBinding(_ slot: Int) -> Binding<MenuBarMetric?> {
        Binding(
            get: { settings.menuBarMetrics.indices.contains(slot) ? settings.menuBarMetrics[slot] : nil },
            set: { value in
                var metrics = settings.menuBarMetrics.map(Optional.some) + Array(repeating: nil, count: 3)
                metrics[slot] = value
                settings.menuBarMetrics = Array(metrics.prefix(3).compactMap { $0 })
            }
        )
    }
}

private struct RunnerTile: View {
    let runner: Runner
    let isSelected: Bool
    let action: () -> Void
    @Local private var preview: NSImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let preview {
                    Image(nsImage: preview).renderingMode(.template)
                } else {
                    Image(systemName: "hare")
                }
                Text(runner.title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.accentBlue.opacity(0.25) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isSelected ? Color.accentBlue : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(runner.title)
        .onAppear { if preview == nil { preview = runner.frames().first } }
    }
}

// MARK: - Sounds

private struct SoundSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Done sound") {
                SoundPicker(selection: $settings.soundChoice)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $settings.soundVolume, in: 0...1) { editing in
                        if !editing { SoundPlayer.shared.play(settings.soundChoice) }
                    }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
            }
            Section("Per job") {
                Toggle("Use a different sound for each job", isOn: $settings.soundPerJob)
                if settings.soundPerJob {
                    ForEach(SoundJob.allCases) { job in
                        let binding = Binding(get: { settings.sound(for: job) }, set: { settings.jobSounds[job] = $0 })
                        HStack {
                            Text(job.title)
                            Spacer()
                            SoundChoiceMenu(selection: binding) { Text("\(binding.wrappedValue.emoji) \(binding.wrappedValue.title)") }
                                .fixedSize()
                        }
                    }
                }
            }
            Section("When to play") {
                QuietHoursEditor(hours: $settings.soundQuietHours, detail: "No sounds during these hours. Notifications still follow your Focus settings")
                Toggle(isOn: $settings.soundsOnlyInBackground) {
                    Described(title: "Only when cfmac is in the background", detail: "Stay quiet while you're looking at cfmac")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cleaning

private struct CleaningSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var autoCleaner: AutoCleaner

    var body: some View {
        Form {
            Section("Cache removal") {
                Picker("When cleaning caches", selection: $settings.deletePermanently) {
                    Text("Move to Trash (restore if needed)").tag(false)
                    Text("Delete permanently").tag(true)
                }
                .pickerStyle(.radioGroup)
                Picker("Starting selection", selection: $settings.cleanPreset) {
                    ForEach(CleanPreset.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.cleanPreset.detail).font(.caption).foregroundStyle(.secondary)
            }
            Section("Automatic cleaning") {
                Picker("Clean Safe items", selection: $settings.autoClean.frequency) {
                    ForEach(AutoCleanPolicy.Frequency.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(
                    isOn: Binding(
                        get: { settings.autoClean.lowDiskGigabytes != nil },
                        set: { settings.autoClean.lowDiskGigabytes = $0 ? 20 : nil }
                    )
                ) {
                    Described(title: "Also when free space is low", detail: "Runs at most every 6 hours")
                }
                if let gigabytes = settings.autoClean.lowDiskGigabytes {
                    Stepper(
                        "Below \(gigabytes) GB free", value: Binding(get: { gigabytes }, set: { settings.autoClean.lowDiskGigabytes = $0 }), in: 5...200,
                        step: 5)
                }
                Text("Only Safe items, always moved to the Trash, never anything an open app is using. You can put a run back from Clean for 24 hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if let run = autoCleaner.lastRun {
                        Text("Last run \(Format.relative(run.date)) · \(Format.bytes(run.freed))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if autoCleaner.isRunning { ProgressView().controlSize(.small) }
                    Button("Clean Now") { autoCleaner.run(reason: "you asked") }.disabled(autoCleaner.isRunning)
                }
            }
            Section("Your folders") {
                ForEach(settings.customFolders) { folder in
                    HStack {
                        Label(Paths.abbreviated(folder.path), systemImage: "folder").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { settings.customFolders.removeAll { $0 == folder } }.buttonStyle(.link)
                    }
                }
                Button("Add Folder…", action: addFolder)
                Text("Clean shows what's inside these folders for you to review. Nothing in them is selected unless you choose it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Items excluded from cleaning") {
                if settings.protectedPaths.isEmpty {
                    Text("No exclusions yet. Right-click an item in Clean › Review and choose Never Clean This.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.protectedPaths, id: \.self) { path in
                        HStack {
                            Text(Paths.abbreviated(path)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Allow in next cleanup") { settings.unprotect(path) }.buttonStyle(.link)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder whose contents Clean should offer for review"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SafetyGuard.check(url.path + "/item", protected: []) == nil, !PrivacyGuard.isPrivate(url.path) else {
            NSSound.beep()
            return
        }
        let folder = CustomCleanFolder(path: url.path)
        if !settings.customFolders.contains(folder) { settings.customFolders.append(folder) }
    }
}

// MARK: - Fan

private struct FanSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var fan: FanController
    @Local private var confirmDisable = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { settings.fanControlEnabled },
                        set: { wantsOn in if wantsOn { fan.showsEnableSheet = true } else { confirmDisable = true } }
                    )
                ) {
                    Described(
                        title: "Fan control",
                        detail: settings.fanControlEnabled ? helperDetail : "Off. Turning it on installs a small helper after showing you what changes")
                }
                .disabled(fan.isWorking)
                if settings.fanControlEnabled, fan.helperState == .outdated || fan.helperState == .unreachable {
                    HStack {
                        Button(fan.helperState == .outdated ? "Update Helper…" : "Reinstall Helper…") { Task { await fan.reinstall() } }
                        if fan.helperState == .unreachable {
                            Button("Open Login Items") { SystemActions.openLoginItemsSettings() }
                                .help("macOS stops background helpers that are switched off under Allow in the Background")
                        }
                    }
                }
                if let message = fan.message { Text(message).font(.caption).foregroundStyle(Color.accentAmber) }
            }
            Group {
                Section("Cool mode curve") {
                    FanCurveEditor(curve: $settings.fanCurve, temperature: fan.temperatures.cpuPeak)
                    Button("Reset Curve") { settings.fanCurve = .standard }.buttonStyle(.link)
                    Toggle(isOn: $settings.fanAutoReturn) {
                        Described(title: "End fan boost after cooling", detail: "Once temperatures drop, macOS controls the fans again")
                    }
                }
                Section("Quiet hours") {
                    QuietHoursEditor(hours: $settings.fanQuietHours, detail: "Cool mode stays gentle at night")
                    if settings.fanQuietHours.isEnabled {
                        VStack(alignment: .leading) {
                            Text("Highest Cool speed: \(Format.percent(settings.fanQuietCap))%")
                            Slider(value: $settings.fanQuietCap, in: 0...1, step: 0.05)
                        }
                    }
                }
                Section("App rules") {
                    ForEach($settings.appFanRules) { $rule in
                        HStack {
                            Text(rule.appName)
                            Spacer()
                            Picker("Mode", selection: $rule.mode) {
                                Text(FanMode.cool.title).tag(FanMode.cool)
                                Text(FanMode.maximum.title).tag(FanMode.maximum)
                            }
                            .labelsHidden()
                            .fixedSize()
                            Button {
                                settings.appFanRules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Menu("Add a Running App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.name) {
                                settings.appFanRules.append(AppFanRule(bundleIdentifier: app.bundleIdentifier, appName: app.name, mode: .cool))
                            }
                        }
                    }
                    Text("While a listed app runs, fans use at least that mode, for example Cool while Xcode builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.fanControlEnabled)
        }
        .formStyle(.grouped)
        .task { await fan.checkHelper() }
        .sheet(isPresented: $fan.showsEnableSheet) { FanEnableSheet() }
        .confirmationDialog("Turn off fan control?", isPresented: $confirmDisable) {
            Button("Turn Off and Remove Helper", role: .destructive) { Task { await fan.disable() } }
        } message: {
            Text("Fans return to macOS, and the helper and its launch configuration are deleted. macOS asks for your password.")
        }
    }

    private var helperDetail: String {
        switch fan.helperState {
        case .checking: "Checking the helper…"
        case .ready: "On · helper installed and running"
        case .notInstalled: "On, but the helper is missing"
        case .outdated: "On · a newer helper ships with this app"
        case .unreachable: "On, but the helper isn't responding"
        }
    }

    private var runningApps: [(bundleIdentifier: String, name: String)] {
        let ruled = Set(settings.appFanRules.map(\.bundleIdentifier))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, !ruled.contains(id), id != Bundle.main.bundleIdentifier else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Watchlist

private struct WatchlistSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Text(
                    "Get told (or have cfmac quit an app) when it uses too much CPU or memory for too long. Checks use the same process list as Status; nothing is recorded."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            ForEach($settings.watchRules) { $rule in
                Section {
                    HStack {
                        TextField("Process name", text: $rule.processName)
                        Toggle("On", isOn: $rule.isEnabled).labelsHidden()
                        Button {
                            settings.watchRules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    Picker("When", selection: $rule.metric) {
                        ForEach(WatchRule.Metric.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper(
                        "is above \(Int(rule.threshold)) \(rule.metric.unit)", value: $rule.threshold,
                        in: rule.metric == .cpu ? 10...800 : 100...32_000, step: rule.metric == .cpu ? 10 : 100)
                    Stepper("for \(Int(rule.minutes)) min", value: $rule.minutes, in: 1...120)
                    Picker("Then", selection: $rule.action) {
                        ForEach(WatchRule.Action.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            Section {
                Button("Add Rule") { settings.watchRules.append(WatchRule(processName: "")) }
                Text("Tip: in Status, right-click a process and choose Watch This Process.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(combo: Binding(get: { settings.shortcuts[action] }, set: { settings.shortcuts[action] = $0 }))
                    }
                }
                Text("Work from any app. Use two or more modifier keys (⌃ ⌥ ⇧ ⌘). These need no special permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Inside cfmac") {
                LabeledContent("Command palette", value: "⌘K")
                LabeledContent("Switch tabs", value: "⌘1 – ⌘5")
                LabeledContent("Previous / next tab", value: "⌘[  ⌘]")
                LabeledContent("Search apps", value: "⌘F")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.shortcuts) { HotKeyCenter.shared.reload() }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Environment(\.openWindow) private var openWindow
    @Local private var confirmErase = false

    var body: some View {
        Form {
            Section("How cfmac treats your data") {
                Label("Reads only file names, sizes and dates. Never opens your documents.", systemImage: "doc.text.magnifyingglass")
                Label(
                    "Never looks inside Photos, Mail, Messages, Contacts, Calendars, Safari or Keychains, even with Full Disk Access.",
                    systemImage: "lock.shield")
                Label("Never asks for the camera, microphone, location, contacts or photos.", systemImage: "hand.raised")
                Label("Everything stays on this Mac. No accounts, analytics or tracking.", systemImage: "desktopcomputer")
                Label("Uses the internet only when you check for or install updates.", systemImage: "network.slash")
                Button("Read the Privacy Statement") { openWindow(id: WindowID.legal, value: LegalDocument.privacy) }
            }
            Section("Full Disk Access") {
                HStack {
                    Described(
                        title: Permissions.hasFullDiskAccess ? "Granted" : "Not granted",
                        detail: "Optional. Lets Clean size more caches and leftovers. Private stores stay off limits either way")
                    Spacer()
                    Button("Open System Settings") { SystemActions.openFullDiskAccessSettings() }
                }
            }
            Section("Your cfmac data") {
                Text("Preferences, lifetime stats, imported sounds and the last automatic clean's undo list. Stored only in your user Library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Erase cfmac Data and Quit…", role: .destructive) { confirmErase = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Erase all cfmac data?", isPresented: $confirmErase) {
            Button("Erase and Quit", role: .destructive, action: LocalData.eraseAndQuit)
        } message: {
            Text("Your settings, stats and imported sounds are deleted. Cleaned files and the fan helper are not affected.")
        }
    }
}

/// Everything cfmac stores, in one place, so it can be erased.
@MainActor
enum LocalData {
    static func eraseAndQuit() {
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        try? FileManager.default.removeItem(at: CustomSoundLibrary.folder.deletingLastPathComponent())
        NSApp.terminate(nil)
    }
}
