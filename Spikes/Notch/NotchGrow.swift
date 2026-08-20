// NotchGrow.swift — does the extension animate, or does it flicker?
//
//   swift Spikes/Notch/NotchGrow.swift [key=value ...]
//
//   ext=160      extension width per side, grown to
//   radius=10    bottom corner radius
//   notch=210    resting width (the notch it is extending)
//   period=2.4   one full out-and-back, in seconds
//   cycles=6     how many
//   center=      where the stand-in notch sits (default: screen middle)
//
// The window is created once at its widest and never resized: a window that grew would be
// asking the window server to re-place it over the menu bar sixty times a second. What moves
// is one layer's bounds, which is Core Animation on a layer we own (PRINCIPLES.md §2).

import AppKit
import QuartzCore

var opts: [String: String] = [:]
for arg in CommandLine.arguments.dropFirst() {
  let parts = arg.split(separator: "=", maxSplits: 1)
  if parts.count == 2 { opts[String(parts[0])] = String(parts[1]) }
}
func num(_ key: String, _ fallback: Double) -> Double { opts[key].flatMap(Double.init) ?? fallback }

let extWidth = num("ext", 160)
let radius = num("radius", 10)
let notchWidth = num("notch", 210)
let period = num("period", 2.4)
let cycles = num("cycles", 6)

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame
let stripHeight =
  screen.safeAreaInsets.top > 0
  ? screen.safeAreaInsets.top : sf.maxY - screen.visibleFrame.maxY
let centerX = num("center", sf.midX)
let maxWidth = notchWidth + extWidth * 2

let frame = NSRect(
  x: centerX - maxWidth / 2, y: sf.maxY - stripHeight, width: maxWidth, height: stripHeight)

final class NotchWindow: NSWindow {
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}

let window = NotchWindow(
  contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.backgroundColor = .clear
window.isOpaque = false
window.hasShadow = false
window.level = .statusBar
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
host.wantsLayer = true
window.contentView = host

// One layer, two rounded bottom corners, pinned to the middle of the window: growing it
// widens both sides at once, and the corner radius is the layer's own rather than a path to
// keep in step with it.
let shape = CALayer()
shape.backgroundColor = NSColor.black.cgColor
shape.cornerRadius = radius
shape.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
// Without this the rounded corners rasterise at 1× and read as steps on a Retina display.
shape.contentsScale = window.backingScaleFactor
shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
shape.position = CGPoint(x: frame.width / 2, y: frame.height / 2)
shape.bounds = CGRect(x: 0, y: 0, width: notchWidth, height: frame.height)
host.layer?.addSublayer(shape)

// The stand-in for what the extension is clearing room for. It rides the growth by sitting
// at a fraction of the layer's width, so nothing here needs a second animation.
let dot = CALayer()
dot.backgroundColor = NSColor.systemGreen.cgColor
dot.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
dot.cornerRadius = 5
dot.contentsScale = window.backingScaleFactor
dot.position = CGPoint(x: extWidth / 2, y: frame.height / 2)
dot.opacity = 0
shape.addSublayer(dot)

window.orderFrontRegardless()

let grow = CABasicAnimation(keyPath: "bounds.size.width")
grow.fromValue = notchWidth
grow.toValue = maxWidth
grow.duration = period / 2
grow.autoreverses = true
grow.repeatCount = Float(cycles)
grow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
shape.add(grow, forKey: "grow")

let fade = CABasicAnimation(keyPath: "opacity")
fade.fromValue = 0
fade.toValue = 1
fade.duration = period / 2
fade.autoreverses = true
fade.repeatCount = Float(cycles)
fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
dot.add(fade, forKey: "fade")

print("screen \(screen.localizedName)  strip \(stripHeight)pt  \(notchWidth)→\(maxWidth)pt")
print("window x=\(frame.minX) w=\(frame.width)  scale \(window.backingScaleFactor)")
print("breathing for \(period * cycles)s")
Timer.scheduledTimer(withTimeInterval: period * cycles, repeats: false) { _ in
  NSApp.terminate(nil)
}
NSApp.run()
