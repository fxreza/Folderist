import AppKit

/// Writes rendered icon images out as a `.iconset` directory, a compiled
/// `.icns` (via `/usr/bin/iconutil`), or a single PNG.
enum ExportService {

    enum ExportError: Error {
        case missingSize(Int)
        case pngEncodingFailed
        case iconutilUnavailable
        case iconutilFailed(status: Int32, output: String)
    }

    /// (iconset file name, source pixel size to draw at). Matches Apple's
    /// required `.iconset` naming exactly.
    static let iconsetEntries: [(name: String, pixelSize: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    /// Writes a `.iconset` directory at `directoryURL` from `images` (keyed
    /// by pixel size, e.g. 16, 32, ... 1024). Entries whose pixel size isn't
    /// present in `images` are skipped (iconutil tolerates a partial set).
    static func writeIconset(images: [Int: NSImage], to directoryURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: directoryURL.path) {
            try fm.removeItem(at: directoryURL)
        }
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for entry in iconsetEntries {
            guard let image = images[entry.pixelSize] else { continue }
            let data = try pngData(for: image, pixelSize: entry.pixelSize)
            try data.write(to: directoryURL.appendingPathComponent(entry.name))
        }
    }

    /// Compiles `images` to a `.icns` file at `icnsURL` by writing a
    /// temporary `.iconset` and shelling out to `/usr/bin/iconutil`.
    static func writeICNS(images: [Int: NSImage], to icnsURL: URL) throws {
        let iconutilPath = "/usr/bin/iconutil"
        guard FileManager.default.isExecutableFile(atPath: iconutilPath) else {
            throw ExportError.iconutilUnavailable
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconsetDir = tmpDir.appendingPathComponent("icon.iconset")
        try writeIconset(images: images, to: iconsetDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: iconutilPath)
        process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw ExportError.iconutilFailed(status: process.terminationStatus, output: output)
        }
    }

    /// Writes a single PNG at `pixelSize` (defaults to the largest, 1024).
    static func writePNG(image: NSImage, pixelSize: Int = 1024, to url: URL) throws {
        let data = try pngData(for: image, pixelSize: pixelSize)
        try data.write(to: url)
    }

    /// Renders `image` into an exact `pixelSize` x `pixelSize` RGBA bitmap and PNG-encodes it.
    static func pngData(for image: NSImage, pixelSize: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ExportError.pngEncodingFailed
        }
        rep.size = NSSize(width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw ExportError.pngEncodingFailed
        }
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.pngEncodingFailed
        }
        return data
    }
}
