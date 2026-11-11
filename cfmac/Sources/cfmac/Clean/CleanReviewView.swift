import CfmacCore
import SwiftUI

struct CleanReviewView: View {
    @EnvironmentObject private var model: CleanModel
    @EnvironmentObject private var settings: AppSettings
    @Local private var expanded: Set<CleanSection> = []

    private static let collapsedRowCount = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.phase = .found
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(PillButtonStyle())
                Spacer()
                presetMenu
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            HStack(alignment: .top, spacing: 14) {
                sidebar.frame(width: 250)
                list
            }
            .padding(.horizontal, 24)

            footer
        }
    }

    private var presetMenu: some View {
        Menu {
            ForEach(CleanPreset.allCases) { preset in
                Button {
                    withAnimation(Motion.content) { model.apply(preset) }
                } label: {
                    if model.matchingPreset == preset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
                .help(preset.detail)
            }
            Divider()
            Button("Use \(model.matchingPreset?.title ?? "this") by default") {
                if let preset = model.matchingPreset { settings.cleanPreset = preset }
            }
            .disabled(model.matchingPreset == nil || model.matchingPreset == settings.cleanPreset)
        } label: {
            Label(model.matchingPreset?.title ?? "Custom selection", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Selection presets")
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(model.groups.enumerated()), id: \.element.section) { index, group in
                    let selected = group.items.filter { model.selection.contains($0.path) }.count
                    Button {
                        model.focusedSection = group.section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: group.section.symbol).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.section.title).font(.system(size: 13, weight: .medium))
                                Text(group.section == .storage ? "Size only" : "\(selected)/\(group.items.count) selected")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondaryText)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                            Text(Format.bytes(model.total(of: group.section)))
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(model.focusedSection == group.section ? Color.ink.opacity(0.1) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .appearEffect(order: index)
                }
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.groups, id: \.section) { group in
                        sectionCard(group.section, group.items).id(group.section)
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: model.focusedSection) { _, section in
                if let section { withAnimation(Motion.content) { proxy.scrollTo(section, anchor: .top) } }
            }
        }
    }

    private func sectionCard(_ section: CleanSection, _ items: [CleanItem]) -> some View {
        let isExpanded = expanded.contains(section)
        let visible = isExpanded ? items : Array(items.prefix(Self.collapsedRowCount))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(section.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(Format.bytes(model.total(of: section))).foregroundStyle(Color.secondaryText).monospacedDigit()
            }
            Text(section.detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)
                .padding(.bottom, 4)
            ForEach(visible) { item in CleanRow(item: item) }
            if items.count > Self.collapsedRowCount, !isExpanded {
                Button("Show \(items.count - Self.collapsedRowCount) more") {
                    _ = withAnimation(Motion.content) { expanded.insert(section) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentBlue)
                .padding(.leading, 34)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cardFill))
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selection.isEmpty ? "Nothing selected" : "\(Format.bytes(model.selectedTotal)) selected")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.numericText())
                Text(settings.deletePermanently ? "Deleted permanently" : "Moved to Trash; empty it to free the space")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Button(settings.deletePermanently ? "Permanently clean \(Format.bytes(model.selectedTotal))" : "Clean \(Format.bytes(model.selectedTotal))") {
                model.clean()
            }
            .buttonStyle(HeroButtonStyle())
            .disabled(model.selection.isEmpty)
            .opacity(model.selection.isEmpty ? 0.5 : 1)
        }
        .animation(Motion.value, value: model.selectedTotal)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.15))
    }
}

struct CleanRow: View {
    @EnvironmentObject private var model: CleanModel
    let item: CleanItem

    var body: some View {
        let owner = model.runningOwner(of: item)
        HStack(spacing: 10) {
            if item.safety == .lookUp {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText).frame(width: 20)
            } else {
                Toggle("Select \(item.label)", isOn: Binding(get: { model.selection.contains(item.path) }, set: { _ in model.toggle(item) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 13)).lineLimit(1)
                    Chip(text: item.safety.rawValue, tint: tint(item.safety)).help(item.safety.help)
                    if let owner {
                        Chip(text: "In use", tint: .accentRed).help("\(owner.localizedName ?? "An app") is using this")
                    }
                }
                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let owner {
                Button("Quit") { owner.terminate() }.buttonStyle(PillButtonStyle(tint: .accentRed))
            }
            if item.safety == .lookUp {
                Button {
                    SystemActions.lookUp(item.lookUpQuery)
                } label: {
                    Label("Look Up", systemImage: "safari")
                }
                .buttonStyle(PillButtonStyle(tint: .accentBlue))
                .help("Search the web for how to free this space safely")
            }
            Text(Format.bytes(item.size)).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") { SystemActions.reveal(item.path) }
            Button("Copy Path") { SystemActions.copy(item.path) }
            Button("Look Up How to Free This Space") { SystemActions.lookUp(item.lookUpQuery) }
            Divider()
            Button("Never Clean This") { withAnimation(Motion.content) { model.neverClean(item) } }
        }
    }

    private func tint(_ safety: Safety) -> Color {
        switch safety {
        case .safe: .accentGreen
        case .review: .accentAmber
        case .lookUp: .accentBlue
        }
    }
}
