import AppKit
import Artwork
import SwiftUI

/// Runner frames loaded once per animal and shared by every view that shows them.
@MainActor
enum RunnerFrameCache {
    private static var cache: [Runner: [NSImage]] = [:]

    static func frames(_ runner: Runner) -> [NSImage] {
        if let frames = cache[runner] { return frames }
        let frames = runner.frames()
        cache[runner] = frames
        return frames
    }
}

/// The chosen runner, animated like the menu bar one: faster as the CPU gets busier.
/// Still when Reduce Motion is on.
struct AnimatedRunner: View {
    let runner: Runner
    var height: CGFloat = 18
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        let frames = RunnerFrameCache.frames(runner)
        if frames.isEmpty {
            Image(systemName: "hare").font(.system(size: height * 0.8))
        } else if settings.motionReduced {
            frame(frames[0])
        } else {
            let interval = RunnerFrames.frameInterval(load: monitor.snapshot.cpu)
            TimelineView(.periodic(from: .now, by: interval)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / interval) % frames.count
                frame(frames[index])
            }
        }
    }

    private func frame(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: height)
    }
}

/// A grid of every runner; picking one changes the menu bar and in-app runner at once.
struct RunnerGrid: View {
    @EnvironmentObject private var settings: AppSettings
    var columns = 4

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(Runner.allCases) { runner in
                let isSelected = settings.runner == runner
                Button {
                    settings.runner = runner
                } label: {
                    VStack(spacing: 4) {
                        if let first = RunnerFrameCache.frames(runner).first {
                            Image(nsImage: first).renderingMode(.template).resizable().scaledToFit().frame(height: 18)
                        } else {
                            Image(systemName: "hare")
                        }
                        Text(runner.title).font(.system(size: 10)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentBlue.opacity(0.25) : Color.primary.opacity(0.05)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentBlue : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(runner.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
