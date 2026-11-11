import AppKit
import CfmacCore
import FanService
import SoundKit
import SwiftUI

/// One thing the palette can do.
struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var keywords: [String] = []
    let perform: @MainActor () -> Void
}

@MainActor
enum PaletteCatalog {
    static func actions(openWindow: OpenWindowAction, openSettings: OpenSettingsAction) -> [PaletteAction] {
        let models = AppModels.shared
        var actions = AppTab.allCases.map { tab in
            PaletteAction(id: "tab.\(tab.rawValue)", title: "Go to \(tab.title)", symbol: "arrow.right.circle", keywords: [tab.windowTitle]) {
                models.router.tab = tab
            }
        }
        actions += [
            PaletteAction(id: "scan", title: "Scan for junk", symbol: "sparkles", keywords: ["clean", "cache"]) {
                models.router.tab = .clean
                models.clean.scan()
            },
            PaletteAction(id: "optimize", title: "Run maintenance", symbol: "wrench.and.screwdriver", keywords: ["optimize", "tune"]) {
                models.router.tab = .optimize
                models.optimize.run()
            },
            PaletteAction(id: "updates", title: "Check for app updates", symbol: "arrow.down.app", keywords: ["homebrew", "app store"]) {
                models.router.tab = .apps
                models.apps.segment = .updates
                models.apps.checkUpdates()
            },
            PaletteAction(id: "autoclean", title: "Clean Safe items now", symbol: "clock.arrow.circlepath", keywords: ["automatic"]) {
                models.autoCleaner.run(reason: "you asked")
            },
            PaletteAction(
                id: "awake", title: models.awake.isActive ? "Stop Keep Screen On" : "Keep Screen On", symbol: "cup.and.saucer",
                keywords: ["awake", "caffeinate", "sleep"]
            ) {
                models.awake.isActive ? models.awake.stop() : models.awake.start(minutes: nil)
            },
            PaletteAction(id: "cleanscreen", title: "Clean Screen", symbol: "sparkles.tv", keywords: ["wipe", "keyboard"]) { CleanScreen.shared.start() },
            PaletteAction(id: "doctor", title: "Run Doctor", symbol: "stethoscope", keywords: ["report", "diagnostics"]) { models.router.showsDoctor = true },
            PaletteAction(id: "stats", title: "Share my stats", symbol: "square.and.arrow.up", keywords: ["card", "milestone"]) {
                models.router.showsStatsCard = true
            },
            PaletteAction(id: "sound", title: "Play my done sound", symbol: "speaker.wave.2", keywords: ["preview", "fart", "flush"]) {
                SoundPlayer.shared.play(models.settings.soundChoice)
            },
            PaletteAction(id: "settings", title: "Open Settings", symbol: "gearshape", keywords: ["preferences"]) { openSettings() },
            PaletteAction(id: "privacy", title: "Privacy statement", symbol: "hand.raised", keywords: ["data"]) {
                openWindow(id: WindowID.legal, value: LegalDocument.privacy)
            },
            PaletteAction(id: "appearance", title: "Switch light / dark", symbol: "circle.lefthalf.filled", keywords: ["theme", "appearance"]) {
                models.settings.appearance = NSApp.effectiveAppearance.isDark ? .light : .dark
            },
            PaletteAction(
                id: "motion", title: models.settings.reduceMotion ? "Turn animations back on" : "Reduce motion", symbol: "figure.walk",
                keywords: ["animation", "planets"]
            ) {
                models.settings.reduceMotion.toggle()
            },
        ]
        if models.settings.fanControlEnabled {
            actions += FanMode.allCases.map { mode in
                PaletteAction(id: "fan.\(mode.rawValue)", title: "Fan: \(mode.title)", symbol: "fan", keywords: ["cooling"]) {
                    Task { await models.fan.select(mode) }
                }
            }
        }
        return actions
    }
}

/// ⌘K: type to find any action, arrows to choose, Return to run, Esc to close.
struct CommandPalette: View {
    @EnvironmentObject private var router: Router
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Local private var query = ""
    @Local private var highlighted = 0
    @FocusState private var focused: Bool

    private var results: [PaletteAction] {
        let all = PaletteCatalog.actions(openWindow: openWindow, openSettings: openSettings)
        return FuzzyMatch.rank(all, query: query) { [$0.title] + $0.keywords }
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { run(results) }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, action in
                            Button {
                                run(action)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: action.symbol).frame(width: 20)
                                    Text(action.title)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(index == highlighted ? Color.accentBlue.opacity(0.25) : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                        if results.isEmpty {
                            Text("No matching command").foregroundStyle(.secondary).padding(20)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
                .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
            }
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(0, results.count - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onExitCommand { router.showsPalette = false }
    }

    private func run(_ results: [PaletteAction]) {
        guard results.indices.contains(highlighted) else { return }
        run(results[highlighted])
    }

    private func run(_ action: PaletteAction) {
        router.showsPalette = false
        action.perform()
    }
}
