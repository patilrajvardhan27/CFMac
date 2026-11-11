import CfmacCore
import SwiftUI

struct AppDetailSheet: View {
    @EnvironmentObject private var model: AppsModel
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    var body: some View {
        let leftovers = model.remnants[app.path] ?? []
        let selected = leftovers.filter { model.remnantSelection.contains($0.path) }
        let bytes = selected.reduce(Int64(0)) { $0 + $1.size } + (model.keepApp ? 0 : app.size)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AppIcon(path: app.path, size: 48)
                VStack(alignment: .leading) {
                    Text(app.name).font(.title2.bold())
                    Text("\(app.bundleIdentifier) · \(app.version)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(get: { !model.keepApp }, set: { model.keepApp = !$0 })) {
                VStack(alignment: .leading) {
                    Text("Application · \(Format.bytes(app.size))")
                    Text("Uncheck to keep the app and only clear its associated data").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Text("Associated data").font(.headline)
            if leftovers.isEmpty {
                Text("No leftover files found.").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(leftovers) { remnant in row(remnant) }.frame(minHeight: 200)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.keepApp ? "Clear Data · \(Format.bytes(bytes))" : "Uninstall · \(Format.bytes(bytes))") {
                    model.uninstallDetail()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isUninstalling || (model.keepApp && selected.isEmpty))
            }
        }
        .padding(24)
        .frame(width: 620, height: 520)
    }

    private func row(_ remnant: Remnant) -> some View {
        HStack {
            Toggle(
                "Remove \(remnant.kind)",
                isOn: Binding(
                    get: { model.remnantSelection.contains(remnant.path) },
                    set: { isOn in
                        if isOn { model.remnantSelection.insert(remnant.path) } else { model.remnantSelection.remove(remnant.path) }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(remnant.kind)
                    Chip(text: remnant.confidence.rawValue, tint: remnant.confidence == .automatic ? .accentGreen : .accentAmber)
                        .help(remnant.confidence.help)
                }
                Text(Paths.abbreviated(remnant.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("Matched by \(remnant.evidence)")
            }
            Spacer()
            Text(Format.bytes(remnant.size)).monospacedDigit()
        }
        .contextMenu { Button("Reveal in Finder") { SystemActions.reveal(remnant.path) } }
    }
}

struct UpdatesList: View {
    @EnvironmentObject private var model: AppsModel
    @Local private var pendingUninstall: AppUpdate? = nil

    var body: some View {
        VStack(spacing: 0) {
            if model.isCheckingUpdates {
                Spacer()
                ProgressView("Checking for updates")
                Spacer()
            } else if model.lastUpdateCheck == nil {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "arrow.down.app").font(.system(size: 34)).foregroundStyle(Color.secondaryText)
                    Text("Check for app updates").font(.system(size: 16, weight: .semibold))
                    Text(
                        "cfmac asks Homebrew and the App Store tools on your Mac, if they're installed. This is the only feature that uses the internet, and it runs only when you ask."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    Button("Check Now") { model.checkUpdates() }.buttonStyle(HeroButtonStyle())
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                let updates = model.visibleUpdates
                HStack(spacing: 6) {
                    Text(updates.isEmpty ? "All apps are up to date" : "Updates Available · \(updates.count)")
                        .font(.system(size: 13, weight: .semibold))
                    if let checked = model.lastUpdateCheck {
                        Text("Checked \(Format.relative(checked))").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    }
                    Spacer()
                    if updates.count > 1 {
                        Button("Update All (\(updates.count))") { model.installAll() }.buttonStyle(PillButtonStyle(tint: .accentGreen))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 6)
                if let note = model.updateNote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentAmber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 6)
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(updates.enumerated()), id: \.element.id) { index, update in
                            row(update).appearEffect(order: min(index, 12))
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .confirmationDialog(
            "Uninstall \(pendingUninstall?.name ?? "")?",
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            presenting: pendingUninstall
        ) { update in
            switch update.source {
            case .formula:
                Button("Uninstall", role: .destructive) { model.uninstallUpdate(update, zap: false) }
            case .cask:
                Button("Uninstall App", role: .destructive) { model.uninstallUpdate(update, zap: false) }
                Button("Uninstall App and Its Data", role: .destructive) { model.uninstallUpdate(update, zap: true) }
            case .appStore:
                Button("Move to Trash", role: .destructive) { model.uninstallUpdate(update, zap: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { update in
            switch update.source {
            case .formula:
                Text("Runs brew uninstall \(update.name). Other packages that depend on it may stop working.")
            case .cask:
                Text("Runs brew uninstall --cask \(update.name). \"App and Its Data\" also removes its settings and caches (--zap).")
            case .appStore:
                Text("Quits the app and moves it to the Trash, along with its app data if that's turned on in Settings.")
            }
        }
    }

    private func row(_ update: AppUpdate) -> some View {
        HStack(spacing: 14) {
            Image(systemName: update.source.symbol).font(.system(size: 20)).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(update.name).font(.system(size: 14, weight: .semibold))
                Text("\(update.installedVersion) → \(update.latestVersion) · \(update.source.rawValue)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            if model.updating.contains(update.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Ignore") { model.ignore(update) }.buttonStyle(PillButtonStyle()).help("Hide update reminders for this item")
                Button {
                    pendingUninstall = update
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(PillButtonStyle(tint: .accentRed))
                .help(update.source == .appStore ? "Uninstall this app" : "Uninstall with Homebrew")
                Button("Update") { model.install(update) }.buttonStyle(PillButtonStyle(tint: .accentGreen))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contextMenu {
            Button("Uninstall \(update.name)…") { pendingUninstall = update }.disabled(model.updating.contains(update.id))
        }
    }
}

struct StartupList: View {
    @EnvironmentObject private var model: AppsModel

    var body: some View {
        if model.isLoadingStartup && model.startupItems.isEmpty {
            VStack {
                Spacer(); ProgressView("Reading startup items"); Spacer()
            }
        } else {
            let items = model.startupItems.filter { model.search.isEmpty || $0.label.localizedCaseInsensitiveContains(model.search) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Login items added by apps are managed in System Settings.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryText)
                        Button("Open Login Items") { SystemActions.openLoginItemsSettings() }.buttonStyle(PillButtonStyle())
                    }
                    group("User background services", items.filter { $0.scope == .userAgent })
                    group("System background services", items.filter { $0.scope != .userAgent })
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [StartupItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) · \(items.count)").font(.system(size: 13, weight: .semibold)).padding(.bottom, 4)
                ForEach(items) { row($0) }
            }
        }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.scope == .userAgent ? "person.crop.circle" : "gearshape")
                .frame(width: 24)
                .foregroundStyle(Color.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 13, weight: .medium))
                    if item.isBroken {
                        Chip(text: "Missing program", tint: .accentRed)
                            .help("The program this item launches no longer exists, so it will not run.")
                    }
                    if item.isDisabled { Chip(text: "Disabled") } else if item.isLoaded { Chip(text: "Running", tint: .accentGreen) }
                }
                Text(item.program ?? item.path)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if item.isManageable {
                Button(item.isDisabled ? "Enable" : "Disable") { model.setEnabled(item, item.isDisabled) }.buttonStyle(PillButtonStyle())
                Button {
                    model.moveToTrash(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(PillButtonStyle(tint: .accentRed))
                .help("Move to Trash. You can restore it from the Trash later.")
            } else {
                Text(item.isApple ? "Apple system item" : "Needs admin, review only")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(.vertical, 8)
        .contextMenu { Button("Reveal in Finder") { SystemActions.reveal(item.path) } }
    }
}
