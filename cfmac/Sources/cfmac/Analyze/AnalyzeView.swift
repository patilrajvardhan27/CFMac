import CfmacCore
import SwiftUI

struct AnalyzeView: View {
    @EnvironmentObject private var model: AnalyzeModel
    @EnvironmentObject private var settings: AppSettings
    @Local private var pendingTrash: DiskEntry?

    private static let palette: [Color] = [
        Color(hex: 0x8A6A5A), Color(hex: 0x8C6A3E), Color(hex: 0x9A5640), Color(hex: 0x7D5A3A),
        Color(hex: 0x6F6A4A), Color(hex: 0x7A4E44), Color(hex: 0x5E6A5A), Color(hex: 0x8A7A5A),
    ]
    private static let maxTiles = 40

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 240).padding(.leading, 16)
            VStack(spacing: 8) {
                header
                treemap
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear { model.start() }
        .alert("Move to Trash?", isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let entry = pendingTrash { withAnimation(Motion.content) { model.moveToTrash(entry) } }
                pendingTrash = nil
            }
            Button("Cancel", role: .cancel) { pendingTrash = nil }
        } message: {
            Text("“\(pendingTrash?.name ?? "")” (\(Format.bytes(pendingTrash?.size ?? 0))) will be moved to the Trash.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            PlanetView(planet: settings.planet(for: .analyze), diameter: 90, busy: model.isScanning).padding(.top, 16)
            Text(model.isScanning ? model.status : "\(model.entries.count) items · \(Format.bytes(model.filesTotal))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.numericText())
                .padding(.vertical, 14)
            HStack(spacing: 14) {
                tab("This Folder", isActive: !model.showsLargestFiles) { model.showsLargestFiles = false }
                tab("Largest Files", isActive: model.showsLargestFiles) { model.showsLargestFiles = true }
                Spacer()
            }
            .padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.showsLargestFiles ? model.largestFiles : model.entries) { entry in row(entry) }
                }
                .animation(Motion.content, value: model.entries.map(\.id))
            }
        }
    }

    private func tab(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? Color.ink : Color.secondaryText)
    }

    private func row(_ entry: DiskEntry) -> some View {
        Button {
            if entry.canOpen { withAnimation(Motion.content) { model.open(entry) } } else { model.selection = entry.path }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.isPrivate ? "lock.fill" : entry.kind.symbol).foregroundStyle(Color.secondaryText).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.showsLargestFiles ? entry.name : model.title(for: entry.path))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(entry.isPrivate ? "Private · not scanned" : entry.isSized ? Format.bytes(entry.size) : "Sizing")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondaryText)
                }
                Spacer()
                if entry.canOpen {
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.secondaryText)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(model.selection == entry.path ? Color.ink.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu(entry) }
    }

    @ViewBuilder
    private func menu(_ entry: DiskEntry) -> some View {
        Button("Reveal in Finder") { SystemActions.reveal(entry.path) }
        if entry.canOpen { Button("Open") { model.open(entry) } }
        Divider()
        Button("Move to Trash…") { pendingTrash = entry }
    }

    // MARK: Header and treemap

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.trail.enumerated()), id: \.offset) { index, path in
                if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Color.secondaryText) }
                let isLast = index == model.trail.count - 1
                Button(model.title(for: path)) { withAnimation(Motion.content) { model.jump(to: index) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: isLast ? .semibold : .regular))
                    .foregroundStyle(isLast ? Color.ink : Color.secondaryText)
            }
            Spacer()
            MeterBar(fraction: model.volume.usedFraction, tint: Color(hex: 0xC9A27A), height: 4).frame(width: 72)
            Text("Files \(Format.bytes(model.filesTotal)) · Used \(Format.bytes(model.volume.used)) / \(Format.bytes(model.volume.total))")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)
                .help("Used matches System Settings and includes system files not listed here.")
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondaryText)
            .help("Refresh current folder")
        }
        .padding(.top, 12)
    }

    private var treemap: some View {
        GeometryReader { geometry in
            let shown = Array(model.entries.filter { $0.size > 0 }.prefix(Self.maxTiles))
            let frames = Treemap.layout(shown.map { Double($0.size) }, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                if let message = model.message {
                    Text(message).foregroundStyle(Color.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shown.isEmpty {
                    ProgressView(model.status).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    let frame = frames[index].insetBy(dx: 2, dy: 2)
                    if frame.width > 1, frame.height > 1 {
                        TreemapTile(
                            title: model.title(for: entry.path), entry: entry,
                            color: Self.palette[index % Self.palette.count],
                            isSelected: model.selection == entry.path, size: frame.size
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .onTapGesture(count: 2) { withAnimation(Motion.content) { model.open(entry) } }
                        .onTapGesture { model.selection = entry.path }
                        .contextMenu { menu(entry) }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
        }
        .animation(Motion.content, value: model.entries.map(\.size))
    }
}

private struct TreemapTile: View {
    let title: String
    let entry: DiskEntry
    let color: Color
    let isSelected: Bool
    let size: CGSize
    @Local private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(isSelected || isHovered ? 1 : 0.85))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.ink.opacity(isSelected ? 0.5 : 0), lineWidth: 1.5)
            }
            .overlay {
                if size.width > 70, size.height > 34 {
                    VStack(spacing: 2) {
                        Label(title, systemImage: entry.kind.symbol).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if size.height > 50 { Text(Format.bytes(entry.size)).font(.system(size: 10)).opacity(0.75) }
                    }
                    .padding(4)
                }
            }
            .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
            .help("\(entry.name) · \(Format.bytes(entry.size)) · \(entry.kind.rawValue)")
    }
}
