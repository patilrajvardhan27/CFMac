import CfmacCore
import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var model: AppsModel
    @Local private var searchOpen = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            Group {
                switch model.segment {
                case .uninstall: UninstallList()
                case .updates: UpdatesList()
                case .startup: StartupList()
                }
            }
            .transition(.opacity)
            .animation(Motion.content, value: model.segment)
        }
        .onAppear { model.loadApps() }
        .sheet(item: $model.detailApp) { app in AppDetailSheet(app: app).environmentObject(model) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            SegmentedPills(selection: Binding(get: { model.segment }, set: select), options: AppsModel.Segment.allCases) { $0.rawValue }
            Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondaryText)
                .help("Refresh")
            Spacer()
            if model.segment == .uninstall {
                ForEach(AppsModel.Sort.allCases, id: \.self) { sort in sortButton(sort) }
            }
            searchField
        }
    }

    private func select(_ segment: AppsModel.Segment) {
        model.segment = segment
        if segment == .startup, model.startupItems.isEmpty { model.loadStartup() }
    }

    private func refresh() {
        switch model.segment {
        case .uninstall: model.loadApps(force: true)
        case .updates: model.checkUpdates()
        case .startup: model.loadStartup()
        }
    }

    private func sortButton(_ sort: AppsModel.Sort) -> some View {
        Button {
            if model.sort == sort { model.ascending.toggle() } else { model.sort = sort; model.ascending = true }
        } label: {
            HStack(spacing: 2) {
                Text(sort.rawValue)
                if model.sort == sort {
                    Image(systemName: model.ascending ? "arrow.up" : "arrow.down").font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: model.sort == sort ? .semibold : .regular))
        .foregroundStyle(model.sort == sort ? Color.ink : Color.secondaryText)
        .padding(.horizontal, 6)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(Motion.content) { searchOpen.toggle() }
                searchFocused = searchOpen
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondaryText)
            .keyboardShortcut("f", modifiers: .command)
            .help("Search (⌘F)")
            if searchOpen || !model.search.isEmpty {
                TextField("Search", text: $model.search)
                    .textFieldStyle(.plain)
                    .frame(width: 140)
                    .focused($searchFocused)
                    .onExitCommand {
                        model.search = ""; withAnimation(Motion.content) { searchOpen = false }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, searchOpen ? 8 : 0)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.ink.opacity(searchOpen ? 0.08 : 0)))
    }
}

/// Segmented control: a capsule track with a sliding highlighted pill.
struct SegmentedPills<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(Motion.tab) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == option ? Color.ink : Color.ink.opacity(0.65))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selection == option {
                                Capsule().fill(Color.ink.opacity(0.14)).matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.ink.opacity(0.06)))
    }
}

struct UninstallList: View {
    @EnvironmentObject private var model: AppsModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoadingApps && model.apps.isEmpty {
                Spacer()
                ProgressView("Reading app list")
                Spacer()
            } else {
                let apps = model.visibleApps
                HStack(spacing: 6) {
                    Text("Installed Apps").font(.system(size: 12, weight: .semibold))
                    Text("\(apps.count) apps · \(Format.bytes(apps.reduce(0) { $0 + $1.size }))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .contentTransition(.numericText())
                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 4)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            AppRow(app: app).appearEffect(order: min(index, 12))
                        }
                    }
                    .padding(.horizontal, 24)
                    .animation(Motion.content, value: apps.map(\.id))
                }
                if !model.checked.isEmpty { selectionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
                if !model.uninstallLog.isEmpty { UninstallLogView().transition(.move(edge: .bottom)) }
            }
        }
        .animation(Motion.content, value: model.checked.isEmpty)
        .animation(Motion.content, value: model.uninstallLog.isEmpty)
    }

    private var selectionBar: some View {
        HStack {
            Text("\(model.checked.count) selected · Removes \(Format.bytes(model.checkedRemovalSize))")
                .font(.system(size: 13, weight: .medium))
                .contentTransition(.numericText())
            Spacer()
            Button("Clear") { model.checked.removeAll() }.buttonStyle(PillButtonStyle())
            Button("Uninstall \(model.checked.count)") { model.uninstallChecked() }
                .buttonStyle(HeroButtonStyle())
                .disabled(model.isUninstalling)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }
}

struct AppRow: View {
    @EnvironmentObject private var model: AppsModel
    let app: InstalledApp
    @Local private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            AppIcon(path: app.path, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.system(size: 14, weight: .semibold))
                metadata
            }
            Spacer()
            if app.requiresVendorUninstaller {
                Button {
                    SystemActions.lookUpUninstall(name: app.name)
                } label: {
                    Label("Look Up How to Uninstall", systemImage: "safari")
                }
                .buttonStyle(PillButtonStyle(tint: .accentBlue))
                .help("\(app.name) ships its own uninstaller. This searches the web for the vendor's removal steps.")
            } else {
                Toggle("Select \(app.name)", isOn: Binding(get: { model.checked.contains(app.path) }, set: { _ in model.toggleChecked(app) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isHovered ? Color.ink.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .onTapGesture { if !app.requiresVendorUninstaller { model.openDetail(app) } }
        .contextMenu {
            Button("Show Associated Data…") { model.openDetail(app) }.disabled(app.requiresVendorUninstaller)
            Button("Reveal in Finder") { SystemActions.reveal(app.path) }
            Button("Look Up How to Uninstall") { SystemActions.lookUpUninstall(name: app.name) }
        }
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Text(app.version)
            Text("·")
            Text(app.size > 0 ? Format.bytes(app.size) : "Sizing…")
            if app.dataSize > 0 { Text("·"); Text("\(Format.bytes(app.dataSize)) data") }
            if app.isIntelOnly { Text("·"); Text("Intel").foregroundStyle(Color.accentAmber) }
            if model.isRunning(app) {
                Text("·"); Text("active now").foregroundStyle(Color.accentGreen)
            } else if let used = app.lastUsed {
                Text("·"); Text("opened \(Format.relative(used))")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.secondaryText)
    }
}

struct UninstallLogView: View {
    @EnvironmentObject private var model: AppsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.isUninstalling ? "Uninstalling…" : "Uninstall result").font(.system(size: 13, weight: .semibold))
                Spacer()
                if !model.isUninstalling { Button("Close") { model.dismissLog() }.buttonStyle(PillButtonStyle()) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.uninstallLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        .padding(14)
        .background(Color.black.opacity(0.25))
    }
}
