import Artwork
import SceneKit
import SwiftUI

/// A rotating 3D planet. `busy` speeds it up while work runs; Reduce Motion holds it still.
struct PlanetView: NSViewRepresentable {
    @EnvironmentObject private var settings: AppSettings
    let planet: Planet
    var diameter: CGFloat = 240
    /// The drawing area; larger than the planet when the moon orbits it.
    var canvas: CGSize?
    var withMoon = false
    var busy = false

    private var canvasSize: CGSize { canvas ?? CGSize(width: diameter * 1.1, height: diameter * 1.1) }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: CGRect(origin: .zero, size: canvasSize))
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.allowsCameraControl = false
        install(in: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if context.coordinator.planet != planet { install(in: view, coordinator: context.coordinator) }
        apply(to: view, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
        coordinator.planetScene = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SCNView, context: Context) -> CGSize? { canvasSize }

    private func install(in view: SCNView, coordinator: Coordinator) {
        let scene = PlanetScene(planet: planet, diameter: diameter, canvas: canvasSize, withMoon: withMoon && planet == .earth)
        coordinator.planetScene = scene
        coordinator.planet = planet
        view.scene = scene.scene
        view.pointOfView = scene.camera
        apply(to: view, coordinator: coordinator)
    }

    private func apply(to view: SCNView, coordinator: Coordinator) {
        let still = settings.motionReduced
        coordinator.planetScene?.setPaused(still)
        coordinator.planetScene?.setSpeed(CGFloat(settings.planetSpeed) * (busy ? 6 : 1))
        // A still planet is drawn once and then costs nothing.
        view.isPlaying = !still
        view.rendersContinuously = false
    }

    @MainActor
    final class Coordinator {
        var planetScene: PlanetScene?
        var planet: Planet?
    }
}

/// A planet with a soft glow behind it; the Sun gets a corona.
struct HaloPlanetView: View {
    let planet: Planet
    var diameter: CGFloat = 80

    var body: some View {
        ZStack {
            if planet == .sun {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0xF5A040, opacity: 0.55), .clear], center: .center,
                            startRadius: diameter * 0.35, endRadius: diameter * 0.75)
                    )
                    .frame(width: diameter * 1.5, height: diameter * 1.5)
            }
            PlanetView(planet: planet, diameter: diameter)
        }
        .frame(width: diameter * 1.1, height: diameter * 1.1)
    }
}
