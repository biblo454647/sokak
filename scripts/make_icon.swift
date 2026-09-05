import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("sokak-icon-" + UUID().uuidString)
let set = temp.appendingPathComponent("Sokak.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let box = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(red: 0.12, green: 0.24, blue: 0.26, alpha: 1), ending: NSColor(red: 0.035, green: 0.075, blue: 0.09, alpha: 1))!.draw(in: box, angle: -90)
    NSColor(red: 0.72, green: 0.86, blue: 0.85, alpha: 0.92).setStroke()
    for (x, y, length) in [(310, 610, 150), (465, 720, 170), (635, 610, 200), (768, 745, 135)] {
        let rain = NSBezierPath(); rain.lineWidth = 25; rain.lineCapStyle = .round
        rain.move(to: NSPoint(x: CGFloat(x), y: CGFloat(y))); rain.line(to: NSPoint(x: CGFloat(x-55), y: CGFloat(y-length))); rain.stroke()
    }
    NSColor(red: 0.87, green: 0.73, blue: 0.49, alpha: 1).setStroke()
    let street = NSBezierPath(); street.lineWidth = 20; street.lineCapStyle = .round
    street.move(to: NSPoint(x: 305, y: 255)); street.curve(to: NSPoint(x: 738, y: 255), controlPoint1: NSPoint(x: 425, y: 205), controlPoint2: NSPoint(x: 620, y: 205)); street.stroke()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: set.appendingPathComponent(name)) }
}
let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", set.path, "-o", destination.appendingPathComponent("Sokak.icns").path]
try task.run(); task.waitUntilExit()
if task.terminationStatus != 0 { exit(task.terminationStatus) }
