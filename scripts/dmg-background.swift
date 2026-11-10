import AppKit
let size = NSSize(width: 720, height: 440)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.955, green: 0.953, blue: 0.94, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
func text(_ value: String, _ rect: NSRect, _ font: NSFont, _ color: NSColor) {
    (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
}
text("smpl.menubar", NSRect(x: 46, y: 338, width: 640, height: 48), .systemFont(ofSize: 34, weight: .semibold), .black)
text("A little order for your menu bar.", NSRect(x: 48, y: 306, width: 630, height: 30), .systemFont(ofSize: 17), .darkGray)
text("→", NSRect(x: 333, y: 170, width: 64, height: 60), .systemFont(ofSize: 42, weight: .light), .gray)
text("Drag the app to Applications to install.", NSRect(x: 48, y: 62, width: 630, height: 28), .systemFont(ofSize: 17, weight: .medium), .darkGray)
text("macOS 27 or later", NSRect(x: 48, y: 34, width: 630, height: 22), .systemFont(ofSize: 12), .gray)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
