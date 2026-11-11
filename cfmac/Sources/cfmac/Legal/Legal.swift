import Artwork
import CfmacCore
import SwiftUI

/// Product identity and legal facts shown in About, the welcome sheet and the bundle.
enum AppInfo {
    static let name = "cfmac"
    static let copyrightHolder = "cfmac contributors"
    static let copyright = "Copyright © 2026 \(copyrightHolder). All rights reserved."
    /// Increase when TERMS.md changes materially; users are asked to accept again.
    static let termsVersion = 1

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "development"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

enum LegalDocument: String, Codable, Hashable, CaseIterable, Identifiable {
    case terms, notices, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Terms of Use"
        case .notices: "Open Source Licenses"
        case .privacy: "Privacy Statement"
        }
    }

    var fileName: String {
        switch self {
        case .terms: "TERMS.md"
        case .notices: "NOTICES.md"
        case .privacy: "PRIVACY.md"
        }
    }

    var blocks: [MarkdownBlock]? {
        guard let url = ArtworkLibrary.resourcesDirectory?.appendingPathComponent(fileName),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return MarkdownBlocks.parse(text)
    }
}

enum WindowID {
    static let main = "main"
    static let about = "about"
    static let legal = "legal"
}

struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            PlanetView(planet: .earth, diameter: 120)
            Text(AppInfo.name).font(.system(size: 26, weight: .bold))
            Text("Version \(AppInfo.version)").font(.callout).foregroundStyle(.secondary)
            Text("Free for everyone. Provided as is; use at your own risk.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Text(AppInfo.copyright).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(LegalDocument.terms.title) { openWindow(id: WindowID.legal, value: LegalDocument.terms) }
                Button(LegalDocument.notices.title) { openWindow(id: WindowID.legal, value: LegalDocument.notices) }
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(width: 380)
    }
}

/// Renders TERMS.md or NOTICES.md from the app bundle.
struct LegalView: View {
    let document: LegalDocument

    var body: some View {
        Group {
            if let blocks = document.blocks {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in MarkdownBlockView(block: block) }
                    }
                    .textSelection(.enabled)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("\(document.title) could not be loaded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .navigationTitle(document.title)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level == 1 ? 0 : 8)
        case .paragraph(let text):
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 8)
        case .preformatted(let text):
            Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        case .rule:
            Divider()
        }
    }

    /// Inline formatting only. Links are shown as plain text: cfmac never opens web pages.
    private func inline(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        attributed.link = nil
        return attributed
    }
}

/// Shown until the current Terms of Use are accepted.
struct WelcomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @Local private var agreed = false

    var body: some View {
        VStack(spacing: 16) {
            PlanetView(planet: .earth, diameter: 110)
            Text("Welcome to cfmac").font(.title.bold())
            Text("Clean system junk, remove and update apps, and keep an eye on your Mac. Free for everyone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                point("checkmark.shield", "Nothing is removed until you review it, and caches go to the Trash by default.")
                point("externaldrive.badge.timemachine", "Keep a current backup. Deleted data may be impossible to recover.")
                point("exclamationmark.triangle", "cfmac is provided as is, without warranty. You use it at your own risk.")
                point("lock", "Everything stays on your Mac. No accounts, no analytics.")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick your “done” sound").font(.headline)
                Text("cfmac plays it when cleaning, maintenance, an uninstall or an update finishes. Tap to hear it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SoundPicker(selection: $settings.soundChoice)
            }
            Toggle(isOn: $agreed) {
                HStack(spacing: 4) {
                    Text("I have read and agree to the")
                    Button("Terms of Use") { openWindow(id: WindowID.legal, value: LegalDocument.terms) }
                        .buttonStyle(.link)
                }
            }
            .toggleStyle(.checkbox)
            Button("Get Started") { settings.acceptedTermsVersion = AppInfo.termsVersion }
                .keyboardShortcut(.defaultAction)
                .disabled(!agreed)
            Text(AppInfo.copyright).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 600)
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).frame(width: 20)
        }
        .font(.callout)
    }
}
