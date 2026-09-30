// Rysuje ikonę aplikacji 1024×1024: kartka z numerowaną listą i spinaczem.
// Uruchom: swift scripts/Ikona.swift build/ikona-1024.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ikona-1024.png"
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Tło: zaokrąglony kwadrat w siatce ikon macOS (824 px z marginesem).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
ctx.addPath(tilePath)
ctx.setFillColor(NSColor(srgbRed: 0.13, green: 0.20, blue: 0.33, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.30, blue: 0.47, alpha: 1),
                    ending: NSColor(srgbRed: 0.10, green: 0.15, blue: 0.26, alpha: 1))!
bg.draw(in: tile, angle: -90)
ctx.restoreGState()

// Kartka.
let paper = CGRect(x: 262, y: 190, width: 500, height: 640)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(CGPath(roundedRect: paper, cornerWidth: 26, cornerHeight: 26, transform: nil))
ctx.setFillColor(NSColor(srgbRed: 0.985, green: 0.975, blue: 0.955, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

// Numerowane pozycje listy.
let ink = NSColor(srgbRed: 0.16, green: 0.22, blue: 0.33, alpha: 1)
let font = NSFont.systemFont(ofSize: 64, weight: .bold)
for (i, width) in [270.0, 230.0, 285.0, 190.0].enumerated() {
    let y = 640 - CGFloat(i) * 118
    let num = NSAttributedString(string: "\(i + 1).", attributes: [.font: font, .foregroundColor: ink])
    num.draw(at: CGPoint(x: 318, y: y - 26))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 412, y: y - 2, width: width, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil))
    ctx.setFillColor(ink.withAlphaComponent(i == 2 ? 0.9 : 0.28).cgColor)
    ctx.fillPath()
}

// Spinacz w kolorze akcentu.
ctx.saveGState()
ctx.translateBy(x: 690, y: 770)
ctx.rotate(by: -0.32)
let clip = CGMutablePath()
clip.move(to: CGPoint(x: 0, y: -150))
clip.addLine(to: CGPoint(x: 0, y: 60))
clip.addArc(center: CGPoint(x: 40, y: 60), radius: 40, startAngle: .pi, endAngle: 0, clockwise: true)
clip.addLine(to: CGPoint(x: 80, y: -190))
clip.addArc(center: CGPoint(x: 25, y: -190), radius: 55, startAngle: 0, endAngle: .pi, clockwise: true)
clip.addLine(to: CGPoint(x: -30, y: 20))
ctx.addPath(clip)
ctx.setLineWidth(22)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: NSColor.black.withAlphaComponent(0.25).cgColor)
ctx.setStrokeColor(NSColor(srgbRed: 0.93, green: 0.55, blue: 0.20, alpha: 1).cgColor)
ctx.strokePath()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
