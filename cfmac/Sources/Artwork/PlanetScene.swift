import AppKit
import Metal
import SceneKit

/// A lit, slowly turning 3D planet sized to `diameter` points inside a `canvas`.
///
/// The camera is orthographic, so one world unit maps to a fixed number of points and the
/// planet's on-screen size never depends on perspective. Earth can carry a cloud layer and an
/// orbiting moon; Saturn gets a textured ring; the Sun glows on its own.
@MainActor
public final class PlanetScene {
    public let scene = SCNScene()
    public let camera = SCNNode()

    private let planet: Planet
    /// Spins about the planet's tilted axis.
    private let spinNode = SCNNode()
    private var orbitNode: SCNNode?
    private var speed: CGFloat = 1

    private static let spinKey = "spin"
    private static let orbitKey = "orbit"

    public init(planet: Planet, diameter: CGFloat, canvas: CGSize, withMoon: Bool = false) {
        self.planet = planet
        scene.background.contents = NSColor.clear

        // One world unit is half the planet's diameter on screen.
        let pointsPerUnit = max(1, diameter) / 2
        let cameraSettings = SCNCamera()
        cameraSettings.usesOrthographicProjection = true
        cameraSettings.orthographicScale = Double(max(1, canvas.height) / 2 / pointsPerUnit)
        cameraSettings.zNear = 0.1
        cameraSettings.zFar = 100
        camera.camera = cameraSettings
        camera.position = SCNVector3(0, 0, 20)
        scene.rootNode.addChildNode(camera)

        let body = SCNNode()
        // Saturn's rings must fit inside the same footprint as a plain planet.
        let scale: CGFloat = planet.hasRings ? 1 / Self.ringOuter : 1
        body.scale = SCNVector3(scale, scale, scale)
        body.eulerAngles.z = -CGFloat(planet.tilt * .pi / 180)
        if planet.hasRings { body.eulerAngles.x = 0.42 }
        scene.rootNode.addChildNode(body)

        spinNode.geometry = Self.sphere(radius: 1, material: Self.surface(for: planet))
        body.addChildNode(spinNode)

        if planet == .earth, let clouds = ArtworkLibrary.image("earth-clouds.jpg") {
            let material = SCNMaterial()
            material.diffuse.contents = clouds
            material.blendMode = .screen
            material.writesToDepthBuffer = false
            material.lightingModel = .lambert
            let cloudNode = SCNNode(geometry: Self.sphere(radius: 1.006, material: material))
            cloudNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: planet.spinPeriod * 0.8)))
            spinNode.addChildNode(cloudNode)
        }

        if planet.hasRings {
            let ring = SCNNode(geometry: Self.ring(inner: Self.ringInner, outer: Self.ringOuter, segments: 128))
            body.addChildNode(ring)
        }

        if withMoon { addMoon(canvas: canvas, pointsPerUnit: pointsPerUnit) }
        addLights()
        spin()
    }

    // MARK: Control

    public func setPaused(_ paused: Bool) {
        scene.isPaused = paused
    }

    /// 1 is the normal pace; larger values spin faster.
    public func setSpeed(_ newSpeed: CGFloat) {
        let clamped = max(0.05, min(20, newSpeed))
        guard abs(clamped - speed) > 0.001 else { return }
        speed = clamped
        spin()
    }

    /// A still image of the current frame with a transparent background.
    public func snapshot(size: CGSize) -> NSImage {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    // MARK: Building blocks

    static let ringInner: CGFloat = 1.24
    static let ringOuter: CGFloat = 2.27

    /// A flat annulus in the XZ plane: two vertices per step around, two triangles per segment.
    /// Texture `u` runs from the inner to the outer edge, matching the ring strip texture.
    static func ring(inner: CGFloat, outer: CGFloat, segments: Int) -> SCNGeometry {
        let steps = max(3, segments)
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        vertices.reserveCapacity((steps + 1) * 2)
        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * .pi * 2
            let (x, z) = (cos(angle), sin(angle))
            vertices.append(SCNVector3(x * inner, 0, z * inner))
            vertices.append(SCNVector3(x * outer, 0, z * outer))
            normals.append(SCNVector3(0, 1, 0))
            normals.append(SCNVector3(0, 1, 0))
            let v = CGFloat(step) / CGFloat(steps)
            coordinates.append(CGPoint(x: 0, y: v))
            coordinates.append(CGPoint(x: 1, y: v))
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(steps * 6)
        for step in 0..<steps {
            let a = UInt32(step * 2)
            indices += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: coordinates)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        if let texture = ArtworkLibrary.image("saturn-ring.png") {
            material.diffuse.contents = texture
        } else {
            material.diffuse.contents = NSColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 0.7)
        }
        material.isDoubleSided = true
        material.lightingModel = .lambert
        geometry.materials = [material]
        return geometry
    }

    private static func sphere(radius: CGFloat, material: SCNMaterial) -> SCNSphere {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 96
        sphere.materials = [material]
        return sphere
    }

    private static func surface(for planet: Planet) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = ArtworkLibrary.image(planet.textureName) ?? planet.baseColor
        if planet == .sun {
            // The Sun lights itself.
            material.lightingModel = .constant
            material.emission.contents = material.diffuse.contents
        } else {
            material.lightingModel = .blinn
            material.specular.contents = NSColor(white: planet == .earth ? 0.25 : 0.05, alpha: 1)
            material.shininess = 0.2
        }
        return material
    }

    private func addMoon(canvas: CGSize, pointsPerUnit: CGFloat) {
        let halfWidth = canvas.width / 2 / pointsPerUnit
        let moonRadius: CGFloat = 0.27
        let distance = max(1.6, min(2.8, halfWidth - moonRadius - 0.1))
        let material = PlanetScene.surface(for: .moon)
        let moon = SCNNode(geometry: PlanetScene.sphere(radius: moonRadius, material: material))
        moon.position = SCNVector3(distance, 0, 0)
        let orbit = SCNNode()
        // A slight tilt so the moon passes in front of and behind the Earth.
        orbit.eulerAngles.x = 0.18
        orbit.eulerAngles.y = 0.6
        orbit.addChildNode(moon)
        scene.rootNode.addChildNode(orbit)
        orbitNode = orbit
    }

    private func addLights() {
        let sunlight = SCNLight()
        sunlight.type = .directional
        sunlight.intensity = 1150
        let lightNode = SCNNode()
        lightNode.light = sunlight
        lightNode.eulerAngles = SCNVector3(-0.35, -0.75, 0)
        scene.rootNode.addChildNode(lightNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 260
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
    }

    private func spin() {
        spinNode.removeAction(forKey: Self.spinKey)
        let period = planet.spinPeriod / Double(speed)
        spinNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: period)), forKey: Self.spinKey)
        if let orbitNode {
            orbitNode.removeAction(forKey: Self.orbitKey)
            orbitNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: period * 2.5)), forKey: Self.orbitKey)
        }
    }
}
