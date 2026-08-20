// NotchDemo.swift — can we put a fake notch on screen, over the menu bar?
//
//   swift Spikes/Notch/NotchDemo.swift [key=value ...]
//
//   screen=0        which NSScreen (default: main)
//   ext=120         extension width per side, in points
//   radius=10       bottom corner radius
//   height=0        strip height; 0 = the screen's own (safe-area top, else menu bar height)
//   notch=200       synthetic notch width, on a screen that has no notch of its own
//   level=statusBar mainMenu | statusBar | popUpMenu | screenSaver | shielding
//   seconds=8       how long to stay up
//   debug=0         1 = tint the two extensions so the seam is visible
//
// Nothing here is Ping's architecture — it is one window and one path, to answer three
// questions: does a window of ours draw over the menu bar, at which level, and does the
// shape read as a notch.

import AppKit
import QuartzCore

// ── arguments ────────────────────────────────────────────────────────────────────────────

var opts: [String: String] = [:]
for arg in CommandLine.arguments.dropFirst() {
  let parts = arg.split(separator: "=", maxSplits: 1)
  if parts.count == 2 { opts[String(parts[0])] = String(parts[1]) }
}
func num(_ key: String, _ fallback: Double) -> Double { opts[key].flatMap(Double.init) ?? fallback }

let extWidth = num("ext", 120)
let radius = num("radius", 10)
let synthNotch = num("notch", 200)
let seconds = num("seconds", 8)
let debug = num("debug", 0) != 0

let levels: [String: NSWindow.Level] = [
  "normal": .normal,
  "floating": .floating,
  "mainMenu": .mainMenu,
  "statusBar": .statusBar,
  "popUpMenu": .popUpMenu,
  "screenSaver": .screenSaver,
  "shielding": NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())),
]
let levelName = opts["level"] ?? "statusBar"
guard let level = levels[levelName] else {
  print("unknown level \(levelName); one of \(levels.keys.sorted())")
  exit(1)
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let screenIndex = Int(num("screen", -1))
let screen =
  screenIndex >= 0 && screenIndex < NSScreen.screens.count
  ? NSScreen.screens[screenIndex] : (NSScreen.main ?? NSScreen.screens[0])

// ── geometry ─────────────────────────────────────────────────────────────────────────────

// The notch we are extending: the real one where the screen has it, a centred stand-in of
// the asked-for width where it does not. Both cases end as one rect in screen coordinates.
let sf = screen.frame
let menuBarHeight = sf.maxY - screen.visibleFrame.maxY
let stripHeight =
  num("height", 0) > 0
  ? num("height", 0)
  : (screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : menuBarHeight)

let notch: NSRect
let isReal: Bool
if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
  notch = NSRect(
    x: l.maxX, y: sf.maxY - stripHeight, width: r.minX - l.maxX, height: stripHeight)
  isReal = true
} else {
  // `center=` puts the stand-in somewhere other than the middle — over the app menus or the
  // status items, where there is menu bar content to actually cover.
  let centerX = num("center", sf.midX)
  notch = NSRect(
    x: centerX - synthNotch / 2, y: sf.maxY - stripHeight,
    width: synthNotch, height: stripHeight)
  isReal = false
}

let frame = NSRect(
  x: notch.minX - extWidth, y: notch.minY,
  width: notch.width + extWidth * 2, height: notch.height)

print("screen        \(screen.localizedName)  \(sf.width)×\(sf.height)")
print("menu bar      \(menuBarHeight)pt   strip \(stripHeight)pt")
print("notch         \(isReal ? "real" : "synthetic") w=\(notch.width) at x=\(notch.minX)")
print("window        x=\(frame.minX) y=\(frame.minY) w=\(frame.width) h=\(frame.height)")
print("level         \(levelName) (\(level.rawValue))")

// ── the shape ────────────────────────────────────────────────────────────────────────────

final class NotchView: NSView {
  let radius: CGFloat
  let ext: CGFloat
  let debug: Bool

  init(frame: NSRect, radius: CGFloat, ext: CGFloat, debug: Bool) {
    self.radius = radius
    self.ext = ext
    self.debug = debug
    super.init(frame: frame)
    wantsLayer = true
  }
  required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { false }

  override func draw(_ dirty: NSRect) {
    let b = bounds
    let r = min(radius, b.height, b.width / 2)
    let p = CGMutablePath()
    // Hangs from the top edge, so only the two bottom corners are ever seen. Square at the
    // top is correct rather than lazy: that edge is off the screen.
    p.move(to: CGPoint(x: b.minX, y: b.maxY))
    p.addLine(to: CGPoint(x: b.minX, y: b.minY + r))
    p.addArc(
      tangent1End: CGPoint(x: b.minX, y: b.minY), tangent2End: CGPoint(x: b.minX + r, y: b.minY),
      radius: r)
    p.addLine(to: CGPoint(x: b.maxX - r, y: b.minY))
    p.addArc(
      tangent1End: CGPoint(x: b.maxX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.minY + r),
      radius: r)
    p.addLine(to: CGPoint(x: b.maxX, y: b.maxY))
    p.closeSubpath()

    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.addPath(p)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()

    if debug {
      // Tint the two extensions so the seam with the real notch is visible in a screenshot.
      ctx.addPath(p)
      ctx.clip()
      ctx.setFillColor(NSColor.systemPink.withAlphaComponent(0.35).cgColor)
      ctx.fill(NSRect(x: b.minX, y: b.minY, width: ext, height: b.height))
      ctx.setFillColor(NSColor.systemTeal.withAlphaComponent(0.35).cgColor)
      ctx.fill(NSRect(x: b.maxX - ext, y: b.minY, width: ext, height: b.height))
    }

    // Stand-in for the content this whole thing exists to make room for: a dot in the left
    // extension, an icon-sized square in the right.
    let dot = NSRect(x: b.minX + ext / 2 - 5, y: b.midY - 5, width: 10, height: 10)
    ctx.setFillColor(NSColor.systemGreen.cgColor)
    ctx.fillEllipse(in: dot)
    let icon = NSRect(x: b.maxX - ext / 2 - 8, y: b.midY - 8, width: 16, height: 16)
    ctx.setFillColor(NSColor.systemOrange.cgColor)
    ctx.addPath(CGPath(roundedRect: icon, cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.fillPath()
  }
}

// `constrain=1` hands the frame back to AppKit, and changes nothing: a borderless window is
// not pushed out of the menu bar strip. The flag is what keeps that measurable.
final class NotchWindow: NSWindow {
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    num("constrain", 0) != 0 ? super.constrainFrameRect(frameRect, to: screen) : frameRect
  }
}

let window = NotchWindow(
  contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.backgroundColor = .clear
window.isOpaque = false
window.hasShadow = false
window.level = level
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
window.contentView = NotchView(
  frame: NSRect(origin: .zero, size: frame.size), radius: radius, ext: extWidth, debug: debug)
window.orderFrontRegardless()

print("up for \(seconds)s — screen-capture the top strip now")
Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in NSApp.terminate(nil) }
NSApp.run()
