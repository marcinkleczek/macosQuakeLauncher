import SwiftUI

// MARK: - Czcionka konsoli Quake'a

/// Oryginalna czcionka gry: lump CONCHARS (128×128 indeksów palety, 256 glifów 8×8)
/// z gfx.wad w id1/pak0.pak, kolorowany paletą gfx/palette.lmp.
/// Znaki 128–255 to te same glify w wersji „złotej" — stąd bierze się kolor.
final class QuakeFont {
    private let chars: [UInt8]
    private let palette: [UInt8]

    init?(baseDir: URL) {
        guard let pak = try? Data(contentsOf: baseDir.appendingPathComponent("id1/pak0.pak")),
              let wad = Self.pakEntry(pak, "gfx.wad"),
              let pal = Self.pakEntry(pak, "gfx/palette.lmp"), pal.count >= 768,
              let glyphs = Self.wadLump(wad, "CONCHARS"), glyphs.count >= 128 * 128
        else { return nil }
        chars = [UInt8](glyphs.prefix(128 * 128))
        palette = [UInt8](pal.prefix(768))
    }

    /// Kod znaku dla Quake'a; poza ASCII/high-bit gra nic sensownego nie wyświetli.
    static func code(_ scalar: UnicodeScalar) -> UInt8 {
        scalar.value <= 0xFF ? UInt8(scalar.value) : 0x3F // '?'
    }

    func image(for text: String) -> NSImage? {
        let codes = text.unicodeScalars.map(Self.code)
        guard !codes.isEmpty else { return nil }
        let width = codes.count * 8, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (i, code) in codes.enumerated() {
            let sx = Int(code % 16) * 8, sy = Int(code / 16) * 8
            for y in 0 ..< 8 {
                for x in 0 ..< 8 {
                    let index = Int(chars[(sy + y) * 128 + sx + x])
                    if index == 0 { continue } // 0 = przezroczysty
                    let o = (y * width + i * 8 + x) * 4
                    pixels[o] = palette[index * 3]
                    pixels[o + 1] = palette[index * 3 + 1]
                    pixels[o + 2] = palette[index * 3 + 2]
                    pixels[o + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    // MARK: Parsery formatów id Software

    private static func u32(_ d: Data, _ offset: Int) -> Int {
        Int(d[offset]) | Int(d[offset + 1]) << 8 | Int(d[offset + 2]) << 16 | Int(d[offset + 3]) << 24
    }

    private static func name(_ d: Data, _ offset: Int, _ length: Int) -> String {
        let bytes = [UInt8](d[offset ..< offset + length]).prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// PAK: nagłówek "PACK" + tablica wpisów po 64 B (56 B nazwa, offset, długość).
    private static func pakEntry(_ pak: Data, _ wanted: String) -> Data? {
        guard pak.count > 12, name(pak, 0, 4) == "PACK" else { return nil }
        let dirOffset = u32(pak, 4), dirLength = u32(pak, 8)
        guard dirOffset + dirLength <= pak.count else { return nil }
        for i in stride(from: 0, to: dirLength, by: 64) {
            let entry = dirOffset + i
            guard name(pak, entry, 56).lowercased() == wanted.lowercased() else { continue }
            let offset = u32(pak, entry + 56), length = u32(pak, entry + 60)
            guard offset + length <= pak.count else { return nil }
            return Data(pak[offset ..< offset + length])
        }
        return nil
    }

    /// WAD2: nagłówek "WAD2" + tablica lumpów po 32 B (pozycja, rozmiary, typ, 16 B nazwa).
    private static func wadLump(_ wad: Data, _ wanted: String) -> Data? {
        guard wad.count > 12, name(wad, 0, 4) == "WAD2" else { return nil }
        let count = u32(wad, 4), table = u32(wad, 8)
        for i in 0 ..< count {
            let entry = table + i * 32
            guard entry + 32 <= wad.count else { return nil }
            guard name(wad, entry + 16, 16).uppercased() == wanted.uppercased() else { continue }
            let offset = u32(wad, entry), length = u32(wad, entry + 8)
            guard offset + length <= wad.count else { return nil }
            return Data(wad[offset ..< offset + length])
        }
        return nil
    }
}
