import AppKit
import Foundation

// Driver for scripts/make-appicon.sh. Compiled together with the app's own
// rendering + export source files (see that script), so it renders the app
// icon through the exact same `FolderIconRenderer` / `ExportService` code
// the app itself uses — no separate icon-drawing path to drift out of sync.
//
// Usage:
//   generate-appicon <symbol> <assetsDir> <previewPNG> [<iconsetDir> <icnsPath>]
//
// With just a symbol + preview path, it renders a single 512px PNG so the
// design can be eyeballed before committing to it. Passing the iconset/icns
// paths additionally writes the full .iconset and compiles the .icns.

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data(
        "usage: generate-appicon <symbol> <assetsDir> <previewPNG> [<iconsetDir> <icnsPath>]\n".utf8))
    exit(64)
}
let symbolName = args[1]
let assetsDir = URL(fileURLWithPath: args[2])
let previewURL = URL(fileURLWithPath: args[3])
let iconsetURL = args.count > 4 ? URL(fileURLWithPath: args[4]) : nil
let icnsURL = args.count > 5 ? URL(fileURLWithPath: args[5]) : nil

// Indigo -> cyan, ~65°: a cool, saturated pair distinct from the stock macOS
// folder blue, at an angle steep enough to read as a diagonal sweep rather
// than a flat left-to-right fade.
let indigo = StyleColor(red: 0.345, green: 0.337, blue: 0.839)
let cyan = StyleColor(red: 0.196, green: 0.808, blue: 0.933)

var style = Style()
style.fill = .gradient(indigo, cyan, angleDegrees: 65)
style.graphic = .sfSymbol(name: symbolName)
// `graphicEffects.emboss` defaults to true — the engraved look is exactly
// what we want here, so the default `Style()` effects are left alone.

let resources = DirectoryRenderResources(baseURL: assetsDir)

do {
    let images = FolderIconRenderer.renderIconSet(style: style, resources: resources)

    if let preview = images[512] {
        try ExportService.writePNG(image: preview, pixelSize: 512, to: previewURL)
        print("Wrote preview: \(previewURL.path)")
    }

    if let iconsetURL, let icnsURL {
        try ExportService.writeIconset(images: images, to: iconsetURL)
        print("Wrote iconset: \(iconsetURL.path)")
        try ExportService.writeICNS(images: images, to: icnsURL)
        print("Wrote icns: \(icnsURL.path)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
