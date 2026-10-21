// Generator tła okna DMG (660×440 pkt, wersje 1x i 2x) — motyw spójny z ikonami.
// Użycie: swift dmgbg.swift <katalog-wyjściowy>  → background.png, background@2x.png
import CoreGraphics
import CoreText
import ImageIO
import Foundation
import UniformTypeIdentifiers

let W: CGFloat = 660, H: CGFloat = 440

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: colors as CFArray, locations: locations)!
}

func render(scale: CGFloat, to url: URL) {
    let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    func flipY(_ y: CGFloat) -> CGFloat { H - y } // współrzędne "od góry" jak w projekcie

    // tło
    ctx.addRect(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x2A1E17), rgb(0x100B08)], [0, 1]),
                           start: CGPoint(x: W / 2, y: H), end: CGPoint(x: W / 2, y: 0), options: [])
    ctx.drawRadialGradient(gradient([rgb(0x8A5A2E, 0.20), rgb(0x000000, 0)], [0, 1]),
                           startCenter: CGPoint(x: W / 2, y: flipY(90)), startRadius: 0,
                           endCenter: CGPoint(x: W / 2, y: flipY(90)), endRadius: 420, options: [])

    // znak wodny: pierścień + gwóźdź, ledwo widoczny, za układem ikon
    let cx: CGFloat = 330, cy: CGFloat = 215
    let rOut: CGFloat = 168, rIn: CGFloat = 116
    let mark = CGMutablePath()
    mark.addEllipse(in: CGRect(x: cx - rOut, y: flipY(cy + rOut), width: rOut * 2, height: rOut * 2))
    mark.addEllipse(in: CGRect(x: cx - rIn, y: flipY(cy + rIn), width: rIn * 2, height: rIn * 2))
    ctx.saveGState()
    ctx.addPath(mark)
    ctx.setFillColor(rgb(0xC89552, 0.07))
    ctx.fillPath(using: .evenOdd)
    let nail = CGMutablePath()
    nail.move(to: CGPoint(x: cx - 58, y: flipY(cy - 140)))
    nail.addLine(to: CGPoint(x: cx + 58, y: flipY(cy - 140)))
    nail.addLine(to: CGPoint(x: cx + 32, y: flipY(cy - 92)))
    nail.addLine(to: CGPoint(x: cx, y: flipY(cy + 230)))
    nail.addLine(to: CGPoint(x: cx - 32, y: flipY(cy - 92)))
    nail.closeSubpath()
    ctx.addPath(nail)
    ctx.setFillColor(rgb(0xC89552, 0.07))
    ctx.fillPath()
    ctx.restoreGState()

    // strzałka: od aplikacji do Applications
    let ay = flipY(222)
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 252, y: ay + 6))
    arrow.addLine(to: CGPoint(x: 392, y: ay + 6))
    arrow.addLine(to: CGPoint(x: 392, y: ay + 24))
    arrow.addLine(to: CGPoint(x: 436, y: ay))
    arrow.addLine(to: CGPoint(x: 392, y: ay - 24))
    arrow.addLine(to: CGPoint(x: 392, y: ay - 6))
    arrow.addLine(to: CGPoint(x: 252, y: ay - 6))
    arrow.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: rgb(0x000000, 0.6))
    ctx.addPath(arrow)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xE0AC64), rgb(0x835723)], [0, 1]),
                           start: CGPoint(x: 340, y: ay + 24), end: CGPoint(x: 340, y: ay - 24), options: [])
    ctx.restoreGState()

    // napisy
    func drawText(_ text: String, centerX: CGFloat, baselineY: CGFloat,
                  size: CGFloat, color: CGColor, kern: CGFloat, weight: String) {
        let font = CTFontCreateWithName("HelveticaNeue-\(weight)" as CFString, size, nil)
        let attrs = [kCTFontAttributeName: font,
                     kCTForegroundColorAttributeName: color,
                     kCTKernAttributeName: kern as CFNumber] as CFDictionary
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, text as CFString, attrs)!)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: centerX - CGFloat(width) / 2, y: baselineY)
        CTLineDraw(line, ctx)
    }
    drawText("QUAKE TOOLS", centerX: W / 2, baselineY: flipY(52),
             size: 19, color: rgb(0xD9A85E, 0.9), kern: 7, weight: "Medium")
    drawText("Drag the apps to the Applications folder", centerX: W / 2, baselineY: flipY(416),
             size: 13, color: rgb(0xB08A55, 0.9), kern: 0.4, weight: "Regular")

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
render(scale: 1, to: outDir.appendingPathComponent("background.png"))
render(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))
print("OK")
