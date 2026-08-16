// Generator ikon: klasyczny motyw Quake (pierścień + gwóźdź) w brązach na ciemnym tle.
// Użycie: swift icons.swift <katalog-wyjściowy>  → QuakeLauncher-icon.png, QuakeConfig-icon.png (1024×1024)
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let size = 1024

func makeContext() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: colors as CFArray, locations: locations)!
}

func fillPath(_ ctx: CGContext, _ path: CGPath, gradientColors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(gradientColors, [0, 1]), start: from, end: to, options: [])
    ctx.restoreGState()
}

// Uwaga: CoreGraphics ma oś Y w górę — rysujemy "do góry nogami" względem intuicji, stąd flip.
func flipY(_ y: CGFloat) -> CGFloat { CGFloat(size) - y }

func drawBackground(_ ctx: CGContext) {
    // kanwa Apple: zaokrąglony kwadrat 824×824 na środku 1024, promień ~186
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x000000, 0.55))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0x17100C))
    ctx.fillPath()
    ctx.restoreGState()
    fillPath(ctx, path,
             gradientColors: [rgb(0x2E211A), rgb(0x150E0A)],
             from: CGPoint(x: 512, y: flipY(100)), to: CGPoint(x: 512, y: flipY(924)))
    // subtelna winieta-poświata u góry
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0x8A5A2E, 0.32), rgb(0x000000, 0)], [0, 1]),
                           startCenter: CGPoint(x: 512, y: flipY(240)), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: flipY(240)), endRadius: 560, options: [])
    ctx.restoreGState()
}

let bronzeLight: [CGColor] = [rgb(0xE8B36A), rgb(0x9C6C33), rgb(0x5C3B1D)]
let bronzeDark: [CGColor] = [rgb(0xC89552), rgb(0x7C5326), rgb(0x422A13)]

func drawQuakeMark(_ ctx: CGContext, center: CGPoint, scale: CGFloat) {
    let cx = center.x, cy = center.y
    let rOuter = 296 * scale, rInner = 196 * scale

    // pierścień (even-odd)
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: cx - rOuter, y: flipY(cy + rOuter), width: rOuter * 2, height: rOuter * 2))
    ring.addEllipse(in: CGRect(x: cx - rInner, y: flipY(cy + rInner), width: rInner * 2, height: rInner * 2))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 26 * scale, color: rgb(0x000000, 0.65))
    ctx.addPath(ring)
    ctx.setFillColor(rgb(0x6B4523))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(ring)
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(gradient(bronzeLight, [0, 0.55, 1]),
                           start: CGPoint(x: cx, y: flipY(cy - rOuter)),
                           end: CGPoint(x: cx, y: flipY(cy + rOuter)), options: [])
    ctx.restoreGState()

    // gwóźdź: łeb u góry, długi klin w dół poza pierścień
    let headW = 210 * scale, headTop = cy - 250 * scale, headH = 88 * scale
    let tipY = cy + 420 * scale, shaftW = 120 * scale
    let nail = CGMutablePath()
    nail.move(to: CGPoint(x: cx - headW / 2, y: flipY(headTop)))
    nail.addLine(to: CGPoint(x: cx + headW / 2, y: flipY(headTop)))
    nail.addLine(to: CGPoint(x: cx + shaftW / 2, y: flipY(headTop + headH)))
    nail.addLine(to: CGPoint(x: cx + shaftW / 2 * 0.9, y: flipY(cy + 180 * scale)))
    nail.addLine(to: CGPoint(x: cx, y: flipY(tipY)))
    nail.addLine(to: CGPoint(x: cx - shaftW / 2 * 0.9, y: flipY(cy + 180 * scale)))
    nail.addLine(to: CGPoint(x: cx - shaftW / 2, y: flipY(headTop + headH)))
    nail.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 22 * scale, color: rgb(0x000000, 0.7))
    ctx.addPath(nail)
    ctx.setFillColor(rgb(0x59391C))
    ctx.fillPath()
    ctx.restoreGState()
    fillPath(ctx, nail, gradientColors: [bronzeDark[0], bronzeDark[2]],
             from: CGPoint(x: cx - shaftW, y: flipY(headTop)),
             to: CGPoint(x: cx + shaftW, y: flipY(tipY)))
    // błysk na trzonie
    let shine = CGPath(rect: CGRect(x: cx - 14 * scale, y: flipY(cy + 320 * scale),
                                    width: 18 * scale, height: 480 * scale), transform: nil)
    fillPath(ctx, shine, gradientColors: [rgb(0xF2CB8A, 0.55), rgb(0xF2CB8A, 0)],
             from: CGPoint(x: cx, y: flipY(headTop)), to: CGPoint(x: cx, y: flipY(tipY)))
}

func drawGear(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
    let teeth = 9
    let path = CGMutablePath()
    let inner = radius * 0.74
    for i in 0 ..< (teeth * 4) {
        let angle = CGFloat(i) / CGFloat(teeth * 4) * .pi * 2
        let r = (i / 2) % 2 == 0 ? radius : inner
        let pt = CGPoint(x: center.x + cos(angle) * r, y: flipY(center.y) + sin(angle) * r)
        i == 0 ? path.move(to: pt) : path.addLine(to: pt)
    }
    path.closeSubpath()
    let hole = radius * 0.34
    path.addEllipse(in: CGRect(x: center.x - hole, y: flipY(center.y) - hole, width: hole * 2, height: hole * 2))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: rgb(0x000000, 0.7))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0x8A5E2D))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(gradient([rgb(0xD9A85E), rgb(0x63401E)], [0, 1]),
                           start: CGPoint(x: center.x, y: flipY(center.y) + radius),
                           end: CGPoint(x: center.x, y: flipY(center.y) - radius), options: [])
    ctx.restoreGState()
}

func save(_ ctx: CGContext, to url: URL) {
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// QuakeLauncher: pełny znak na środku
let launcherCtx = makeContext()
drawBackground(launcherCtx)
drawQuakeMark(launcherCtx, center: CGPoint(x: 512, y: 470), scale: 1.0)
save(launcherCtx, to: outDir.appendingPathComponent("QuakeLauncher-icon.png"))

// QuakeConfig: znak mniejszy, przesunięty + zębatka
let configCtx = makeContext()
drawBackground(configCtx)
drawQuakeMark(configCtx, center: CGPoint(x: 448, y: 430), scale: 0.82)
drawGear(configCtx, center: CGPoint(x: 726, y: 726), radius: 160)
save(configCtx, to: outDir.appendingPathComponent("QuakeConfig-icon.png"))
print("OK")
