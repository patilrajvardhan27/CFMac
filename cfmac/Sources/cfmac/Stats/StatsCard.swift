import AppKit
import Artwork
import CfmacCore
import SwiftUI
import UniformTypeIdentifiers

/// The shareable image: lifetime totals and milestones. It contains no name, username,
/// computer name or file paths, and is only ever copied or saved where the user chooses.
struct StatsCard: View {
    let bytesCleaned: Int64
    let cleanRuns: Int
    let optimizeRuns: Int
    let appsUninstalled: Int
    let since: Date
    let planet: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x272B40), Color(hex: 0x12131C)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let planet {
                Image(nsImage: planet).resizable().frame(width: 230, height: 230).offset(x: 400, y: 70)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("cfmac").font(.system(size: 15, weight: .semibold)).opacity(0.7)
                Text("I've freed").font(.system(size: 22, weight: .medium)).opacity(0.85)
                Text(Format.bytes(bytesCleaned)).font(.system(size: 64, weight: .bold, design: .rounded))
                Text("on my Mac since \(since.formatted(.dateTime.month(.wide).year()))").font(.system(size: 16)).opacity(0.7)
                HStack(spacing: 18) {
                    stat("\(cleanRuns)", "cleans")
                    stat("\(optimizeRuns)", "tune-ups")
                    stat("\(appsUninstalled)", "apps removed")
                }
                .padding(.top, 10)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Milestones.thresholds.filter { bytesCleaned >= $0 }.suffix(4), id: \.self) { badge($0) }
                }
            }
            .padding(30)
        }
        .foregroundStyle(.white)
        .frame(width: 640, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 12)).opacity(0.65)
        }
    }

    private func badge(_ threshold: Int64) -> some View {
        Text("🏆 \(Format.bytes(threshold))")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}

/// Preview of the card with Copy and Save. Rendering happens on this Mac only.
struct StatsCardSheet: View {
    @EnvironmentObject private var stats: UsageStats
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Local private var planet: NSImage?
    @Local private var note: String?

    private var card: StatsCard {
        StatsCard(
            bytesCleaned: stats.bytesCleaned, cleanRuns: stats.cleanRuns, optimizeRuns: stats.optimizeRuns,
            appsUninstalled: stats.appsUninstalled, since: stats.firstUse, planet: planet)
    }

    var body: some View {
        VStack(spacing: 14) {
            card.environment(\.colorScheme, .dark)
            if let next = Milestones.next(after: stats.bytesCleaned) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next milestone: \(Format.bytes(next.target))").font(.caption)
                    ProgressView(value: next.progress)
                }
            }
            HStack {
                Text(note ?? "Contains only these totals. Nothing is uploaded.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy Image") { copy() }
                Button("Save Image…") { save() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 690)
        .task {
            // A still frame of the 3D planet; ImageRenderer cannot draw live SceneKit views.
            let size = CGSize(width: 460, height: 460)
            planet = PlanetScene(planet: settings.planet(for: .clean), diameter: 420, canvas: size).snapshot(size: size)
        }
    }

    private func rendered() -> NSImage? {
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark))
        renderer.scale = 2
        return renderer.nsImage
    }

    private func copy() {
        guard let image = rendered() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        note = "Copied. Paste it anywhere you like."
    }

    private func save() {
        guard let image = rendered(), let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "cfmac-stats.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            note = "Saved."
        } catch {
            note = "Couldn't save the image."
        }
    }
}
