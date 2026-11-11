// Build-time helpers for cfmac.
//   cfmac-tools icon <iconset-folder>   render the app icon set
//   cfmac-tools planets <folder>        render each planet to PNG for review
//   cfmac-tools sounds <folder>         export each synthesized completion sound as WAV
import AppKit
import Artwork
import SoundKit

@MainActor
enum Tools {
    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count == 3 else { return usage() }
        let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            switch arguments[1] {
            case "icon": try writeIconSet(to: output)
            case "planets": try writePlanets(to: output)
            case "sounds": try writeSounds(to: output)
            default: return usage()
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("cfmac-tools: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    static func usage() -> Int32 {
        FileHandle.standardError.write(Data("usage: cfmac-tools icon|planets|sounds <folder>\n".utf8))
        return 64
    }

    static func writeSounds(to folder: URL) throws {
        for effect in SynthEffect.allCases {
            try WAV.encode(SoundSynth.render(effect)).write(to: folder.appendingPathComponent("\(effect.rawValue).wav"))
        }
    }

    static func writePlanets(to folder: URL) throws {
        for planet in Planet.allCases {
            let image = PlanetScene(planet: planet, diameter: 400, canvas: CGSize(width: 440, height: 440)).snapshot(size: CGSize(width: 440, height: 440))
            try png(image, pixels: 440).write(to: folder.appendingPathComponent("\(planet.rawValue).png"))
        }
        let hero = PlanetScene(planet: .earth, diameter: 240, canvas: CGSize(width: 780, height: 420), withMoon: true)
        try png(hero.snapshot(size: CGSize(width: 780, height: 420)), width: 780, height: 420).write(to: folder.appendingPathComponent("earth-with-moon.png"))
    }

    /// The app icon: the Earth on a deep-space rounded square.
    static func writeIconSet(to folder: URL) throws {
        let planet = PlanetScene(planet: .earth, diameter: 600, canvas: CGSize(width: 1024, height: 1024)).snapshot(size: CGSize(width: 1024, height: 1024))
        let sizes: [(String, Int)] = [
            ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
            ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            try png(icon(planet: planet, pixels: pixels), pixels: pixels).write(to: folder.appendingPathComponent("icon_\(name).png"))
        }
    }

    static func icon(planet: NSImage, pixels: Int) -> NSImage {
        let side = CGFloat(pixels)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let inset = side * 0.1
            let tile = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
            NSGradient(colors: [NSColor(red: 0.16, green: 0.18, blue: 0.30, alpha: 1), NSColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1)])?
                .draw(in: shape, angle: -90)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let glow = NSGradient(colors: [NSColor(red: 0.35, green: 0.6, blue: 1, alpha: 0.35), .clear])
            glow?.draw(
                fromCenter: NSPoint(x: side / 2, y: side / 2), radius: 0, toCenter: NSPoint(x: side / 2, y: side / 2), radius: tile.width * 0.48, options: [])
            planet.draw(in: tile.insetBy(dx: tile.width * 0.02, dy: tile.width * 0.02))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    static func png(_ image: NSImage, pixels: Int) throws -> Data {
        try png(image, width: pixels, height: pixels)
    }

    static func png(_ image: NSImage, width: Int, height: Int) throws -> Data {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}

exit(MainActor.assumeIsolated { Tools.run(CommandLine.arguments) })
