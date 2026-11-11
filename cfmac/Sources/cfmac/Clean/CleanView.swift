import CfmacCore
import SwiftUI

struct CleanView: View {
    @EnvironmentObject private var model: CleanModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var autoCleaner: AutoCleaner

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle, .found, .scanning, .cleaning:
                hero.transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .review:
                CleanReviewView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .done:
                CleanResultView().transition(.opacity)
            }
        }
        .animation(Motion.content, value: model.phase)
    }

    private var isWorking: Bool { model.phase == .scanning || model.phase == .cleaning }

    private var hero: some View {
        VStack(spacing: 0) {
            if !model.hasFullDiskAccess, model.phase == .idle || model.phase == .found {
                PermissionBanner().padding(.top, 4)
            }
            if autoCleaner.canUndo, let run = autoCleaner.lastRun, model.phase == .idle || model.phase == .found {
                AutoCleanBanner(run: run).padding(.top, 4)
            }
            Spacer(minLength: 0)
            PlanetView(planet: settings.planet(for: .clean), diameter: 240, canvas: CGSize(width: 780, height: 380), withMoon: true, busy: isWorking)
            Spacer().frame(height: 36)
            heroText.frame(height: 130, alignment: .top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var heroText: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .scanning, .cleaning:
                Text(model.phase == .scanning ? "Scanning" : "Cleaning your caches")
                    .font(.system(size: 28, weight: .bold))
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                    .contentTransition(.opacity)
                MeterBar(fraction: model.progress, tint: Color.ink.opacity(0.85), height: 4).frame(width: 236)
                if model.phase == .scanning {
                    Button("Cancel") { model.cancelScan() }.buttonStyle(PillButtonStyle()).padding(.top, 14)
                }
            case .found:
                Text("\(Format.bytes(model.foundTotal)) found")
                    .font(.system(size: 28, weight: .bold))
                    .contentTransition(.numericText())
                HeroSubtitle(text: "\(Format.bytes(model.cleanableTotal)) cleanable ·", link: "Scan again") { model.scan() }
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                Button("Review results") { model.phase = .review }
                    .buttonStyle(HeroButtonStyle())
                    .keyboardShortcut(.defaultAction)
            default:
                Text("Ready to freshen up")
                    .font(.system(size: 28, weight: .bold))
                HeroSubtitle(text: "Caches, logs and leftovers. Nothing is removed until you review it.")
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                Button("Scan") { model.scan() }
                    .buttonStyle(HeroButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .animation(Motion.content, value: model.phase)
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(Color.accentAmber)
            Text("Enable Full Disk Access so cfmac can clean more thoroughly and free up more space.")
                .font(.system(size: 12))
            Spacer()
            Button("Settings") { SystemActions.openFullDiskAccessSettings() }
                .buttonStyle(PillButtonStyle(tint: .accentAmber))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentAmber.opacity(0.1)))
        .padding(.horizontal, 24)
        .appearEffect()
    }
}

/// Offers to put back what the last automatic clean moved to the Trash.
struct AutoCleanBanner: View {
    @EnvironmentObject private var autoCleaner: AutoCleaner
    let run: AutoCleaner.Run

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.accentGreen)
            Text("Automatic clean freed \(Format.bytes(run.freed)) \(Format.relative(run.date)).")
                .font(.system(size: 12))
            Spacer()
            Button("Put Back") { autoCleaner.undo() }.buttonStyle(PillButtonStyle(tint: .accentGreen))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentGreen.opacity(0.1)))
        .padding(.horizontal, 24)
        .appearEffect()
    }
}
