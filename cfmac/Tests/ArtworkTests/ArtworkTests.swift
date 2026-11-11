import AppKit
import Testing

@testable import Artwork

@Suite("Artwork")
struct ArtworkTests {
    @Test func runnerSpeedsUpWithLoad() {
        let idle = RunnerFrames.frameInterval(load: 0)
        let busy = RunnerFrames.frameInterval(load: 1)
        #expect(idle > busy)
        #expect(busy > 0)
        #expect(RunnerFrames.frameInterval(load: 5) == busy)
        #expect(RunnerFrames.frameInterval(load: -1) == idle)
    }

    /// Renders offscreen; without bundled textures the planet's base color is used.
    @MainActor
    @Test(arguments: Planet.allCases)
    func rendersAVisiblePlanet(planet: Planet) throws {
        let size = CGSize(width: 64, height: 64)
        let image = PlanetScene(planet: planet, diameter: 56, canvas: size).snapshot(size: size)
        let bitmap = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init))
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        let corner = try #require(bitmap.colorAt(x: 0, y: 0))
        #expect(center.alphaComponent > 0.9)
        #expect(corner.alphaComponent < 0.1)
    }
}

@Suite("Saturn rings")
struct RingTests {
    @MainActor
    @Test func ringMeshHasTwoTrianglesPerSegment() throws {
        let ring = PlanetScene.ring(inner: 1, outer: 2, segments: 10)
        let vertices = try #require(ring.sources(for: .vertex).first)
        #expect(vertices.vectorCount == 22)
        #expect(ring.elements.first?.primitiveCount == 20)
    }
}
