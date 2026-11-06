// Draws the NotchClip app icon: a black panel dropping out of a notch, holding clip cards.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon.png")
let orange = NSColor(red: 1, green: 0.384, blue: 0, alpha: 1)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded-square tile with a soft grey gradient.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(white: 0.23, alpha: 1), ending: NSColor(white: 0.12, alpha: 1))?
    .draw(in: tilePath, angle: -90)

// The panel growing out of the top edge.
NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
let panel = NSBezierPath()
let left: CGFloat = 210, right: CGFloat = 814, bottom: CGFloat = 330, radius: CGFloat = 90
panel.move(to: NSPoint(x: left, y: 930))
panel.line(to: NSPoint(x: left, y: bottom + radius))
panel.appendArc(withCenter: NSPoint(x: left + radius, y: bottom + radius), radius: radius, startAngle: 180, endAngle: 270)
panel.line(to: NSPoint(x: right - radius, y: bottom))
panel.appendArc(withCenter: NSPoint(x: right - radius, y: bottom + radius), radius: radius, startAngle: 270, endAngle: 360)
panel.line(to: NSPoint(x: right, y: 930))
panel.close()
NSColor.black.setFill()
panel.fill()
NSGraphicsContext.restoreGraphicsState()

// Three clip cards; the picked one is orange.
let cardWidth: CGFloat = 158, gap: CGFloat = 30, cardTop: CGFloat = 740, cardBottom: CGFloat = 400
for index in 0..<3 {
    let x = 257 + CGFloat(index) * (cardWidth + gap)
    let card = NSRect(x: x, y: cardBottom, width: cardWidth, height: cardTop - cardBottom)
    let path = NSBezierPath(roundedRect: card, xRadius: 34, yRadius: 34)
    (index == 1 ? orange : NSColor(white: 1, alpha: 0.16)).setFill()
    path.fill()
    let lineColor = index == 1 ? NSColor(white: 0, alpha: 0.55) : NSColor(white: 1, alpha: 0.35)
    lineColor.setFill()
    for (row, width) in [(0, 0.72), (1, 0.55), (2, 0.66)] {
        let y = cardTop - 70 - CGFloat(row) * 52
        NSBezierPath(roundedRect: NSRect(x: x + 26, y: y, width: (cardWidth - 52) * width / 0.72, height: 22),
                     xRadius: 11, yRadius: 11).fill()
    }
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
