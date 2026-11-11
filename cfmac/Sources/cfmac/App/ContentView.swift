import Artwork
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: router.tab.gradient(tint: settings.tabTints[router.tab.rawValue]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(Motion.tab, value: router.tab)

            VStack(spacing: 0) {
                ZStack {
                    TabBar()
                    HStack {
                        SoundMenuPill()
                        Spacer()
                        FreePill()
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                .padding(.bottom, 8)

                ZStack {
                    switch router.tab {
                    case .clean: CleanView()
                    case .apps: AppsView()
                    case .optimize: OptimizeView()
                    case .analyze: AnalyzeView()
                    case .status: StatusView()
                    }
                }
                .id(router.tab)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(Motion.tab, value: router.tab)
        .foregroundStyle(Color.ink)
        .frame(minWidth: 1000, minHeight: 700)
        .ignoresSafeArea()
        .navigationTitle(router.tab.windowTitle)
        .overlay(alignment: .top) {
            if router.showsPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { router.showsPalette = false }
                    CommandPalette().padding(.top, 110)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.content, value: router.showsPalette)
        .onAppear { WindowOpener.openWindow = openWindow }
        .sheet(isPresented: $router.showsDoctor) { DoctorView() }
        .sheet(isPresented: $router.showsStatsCard) { StatsCardSheet() }
        .sheet(isPresented: Binding(get: { settings.acceptedTermsVersion < AppInfo.termsVersion }, set: { _ in })) {
            WelcomeView()
        }
    }
}

/// Centered capsule with the runner mark and five tabs; the selected tab is a sliding pill.
private struct TabBar: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var settings: AppSettings
    @Namespace private var namespace
    @Local private var showsRunners = false

    var body: some View {
        HStack(spacing: 2) {
            Button {
                showsRunners.toggle()
            } label: {
                ZStack {
                    Circle().fill(Color.ink)
                    AnimatedRunner(runner: settings.runner, height: 16).foregroundStyle(Color.inkInverse).padding(.horizontal, 5)
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Change runner: \(settings.runner.title)")
            .accessibilityLabel("Change runner, currently \(settings.runner.title)")
            .popover(isPresented: $showsRunners, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Runner").font(.headline)
                    Text("Shown here and in the menu bar. Runs faster as your Mac gets busier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RunnerGrid(columns: 5)
                }
                .padding(14)
                .frame(width: 380)
            }

            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(Motion.tab) { router.tab = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(router.tab == tab ? Color.inkInverse : Color.ink.opacity(0.75))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background {
                            if router.tab == tab {
                                Capsule().fill(Color.ink).matchedGeometryEffect(id: "selectedTab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(router.tab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.ink.opacity(0.08)))
        .accessibilityHint("Press Command 1 through 5 to switch tabs")
    }
}

/// Top-right status pill: cfmac is free; opens About.
private struct FreePill: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: WindowID.about)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.accentGreen).frame(width: 6, height: 6)
                Text("Free").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentGreen.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.accentGreen.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .help("cfmac is free. About, terms and licenses")
    }
}
