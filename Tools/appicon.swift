// Składa ikonę aplikacji z kwadratowej grafiki: przycina do zaokrąglonego kwadratu
// Apple (824×824 na kanwie 1024, promień ~186), dodaje cień i zapisuje .icns.
// Użycie: swift Tools/appicon.swift <grafika.jpg> <wyjście.icns>
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("Użycie: swift Tools/appicon.swift <grafika.jpg> <wyjście.icns>")
    exit(1)
}
let output = URL(fileURLWithPath: args[2])

func render(pixels: Int) -> CGImage {
    let s = CGFloat(pixels) / 1024
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let rect = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = CGPath(roundedRect: rect, cornerWidth: 186 * s, cornerHeight: 186 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 36 * s,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(srgbRed: 0.09, green: 0.06, blue: 0.05, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(art, in: rect)
    return ctx.makeImage()!
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let dest = CGImageDestinationCreateWithURL(iconset.appendingPathComponent(name) as CFURL,
                                                   UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, render(pixels: points * scale), nil)
        CGImageDestinationFinalize(dest)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "OK: \(output.path)" : "iconutil: błąd \(iconutil.terminationStatus)")
exit(iconutil.terminationStatus)
