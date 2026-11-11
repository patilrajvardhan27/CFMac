import CfmacCore
import SwiftUI

struct ProcessTable: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var settings: AppSettings
    @Local private var sortByCPU = false
    @Local private var search = ""
    @Local private var searchOpen = false
    @Local private var pinned: Set<Int32> = []
    @Local private var pendingSignal: PendingSignal?
    @Local private var errorText: String?

    private static let visibleRows = 80
    /// %CPU above which a process is marked as hot (100% is one busy core).
    private static let hotCPU: Double = 80

    struct PendingSignal: Identifiable {
        let process: ProcessRow
        let force: Bool
        var id: Int32 { process.pid }
    }

    private var rows: [ProcessRow] {
        var list = monitor.snapshot.processes
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || String($0.pid) == search }
        }
        list.sort { lhs, rhs in
            let lhsPinned = pinned.contains(lhs.pid)
            if lhsPinned != pinned.contains(rhs.pid) { return lhsPinned }
            return sortByCPU ? lhs.cpu > rhs.cpu : lhs.memory > rhs.memory
        }
        return Array(list.prefix(Self.visibleRows))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { process in row(process) }
                }
                .animation(Motion.content, value: rows.map(\.pid))
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.cardStroke))
        .alert(item: $pendingSignal) { pending in
            Alert(
                title: Text(pending.force ? "Force quit \(pending.process.name)?" : "Stop \(pending.process.name)?"),
                message: Text(
                    pending.force
                        ? "Force Quit ends the process immediately, so unsaved data may be lost." : "cfmac will ask it to stop. Unsaved work may be lost."),
                primaryButton: .destructive(Text(pending.force ? "Force Quit" : "Terminate")) { send(pending) },
                secondaryButton: .cancel()
            )
        }
        .alert(errorText ?? "", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("NAME (\(monitor.snapshot.processes.count))").frame(maxWidth: .infinity, alignment: .leading)
            sortHeader("MEM", isActive: !sortByCPU) { sortByCPU = false }.frame(width: 90, alignment: .trailing)
            sortHeader("% CPU", isActive: sortByCPU) { sortByCPU = true }.frame(width: 170, alignment: .trailing)
            Text("PID").frame(width: 80, alignment: .trailing)
            HStack(spacing: 4) {
                if searchOpen {
                    TextField("Search", text: $search).textFieldStyle(.plain).frame(width: 80)
                        .onExitCommand {
                            search = ""; searchOpen = false
                        }
                }
                Button {
                    withAnimation(Motion.content) { searchOpen.toggle() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
            }
            .frame(width: searchOpen ? 112 : 44, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.secondaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func sortHeader(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).foregroundStyle(isActive ? Color.ink : Color.secondaryText) }.buttonStyle(.plain)
    }

    private func row(_ process: ProcessRow) -> some View {
        let isHot = process.cpu > Self.hotCPU
        return HStack(spacing: 0) {
            Capsule().fill(isHot ? Color.accentRed : .clear).frame(width: 3, height: 18).padding(.trailing, 8)
            Group {
                if let app = process.appPath { AppIcon(path: app, size: 18) } else { Image(systemName: "terminal").frame(width: 18) }
            }
            .padding(.trailing, 8)
            Text(process.name).font(.system(size: 13)).lineLimit(1)
            if isHot {
                SpinningSymbol(name: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentRed)
                    .padding(.leading, 6)
                    .help("Using sustained high CPU")
            }
            if pinned.contains(process.pid) {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color.secondaryText).padding(.leading, 4)
            }
            Spacer()
            Text(Format.bytes(process.memory)).frame(width: 90, alignment: .trailing)
            MeterBar(fraction: min(1, process.cpu / 100), tint: isHot ? .accentRed : Color.ink.opacity(0.6), height: 5)
                .frame(width: 50)
                .padding(.leading, 40)
            Text(String(format: "%.1f", process.cpu))
                .foregroundStyle(isHot ? Color.accentRed : Color.ink)
                .frame(width: 80, alignment: .trailing)
            Text("\(process.pid)").foregroundStyle(Color.secondaryText).frame(width: 80, alignment: .trailing)
            Menu {
                menu(process)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .padding(.leading, 14)
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contextMenu { menu(process) }
    }

    @ViewBuilder
    private func menu(_ process: ProcessRow) -> some View {
        Button("Terminate") { pendingSignal = PendingSignal(process: process, force: false) }
        Button("Force Quit") { pendingSignal = PendingSignal(process: process, force: true) }
        Divider()
        Button(pinned.contains(process.pid) ? "Unpin Row" : "Pin Row") {
            if pinned.remove(process.pid) == nil { pinned.insert(process.pid) }
        }
        Button("Reveal in Finder") { SystemActions.reveal(process.appPath ?? process.path) }
        Button("Copy Process Name") { SystemActions.copy(process.name) }
        Button("Copy PID") { SystemActions.copy("\(process.pid)") }
        Divider()
        Button("Watch This Process") { watch(process) }
            .disabled(settings.watchRules.contains { $0.processName.caseInsensitiveCompare(process.name) == .orderedSame })
    }

    /// Adds a Watchlist rule (notify when over 80% CPU for 5 minutes); edit it in Settings › Watchlist.
    private func watch(_ process: ProcessRow) {
        settings.watchRules.append(WatchRule(processName: process.name))
        errorText = "Watching \(process.name): you'll be told if it uses over 80% CPU for 5 minutes. Change this in Settings › Watchlist."
    }

    private func send(_ pending: PendingSignal) {
        switch ProcessList.signal(pending.process, force: pending.force) {
        case .sent: break
        case .protectedProcess: errorText = "System process, cannot be terminated"
        case .changed: errorText = "The process changed, refresh and try again"
        case .permissionDenied: errorText = "Permission denied"
        case .gone: errorText = "Process is no longer running"
        }
    }
}
