import AppKit
import PingConfig
import PingCore
import Testing

@testable import PingUI

/// Where an indicator ends up once the layout's arithmetic has become layers.
///
/// `NotchLayoutTests` settles how many slots a side is owed; this settles that the slot is where
/// the eye expects it — one gap from the cutout, inside the shape that is meant to reveal it.
@Suite("Notch strip")
@MainActor
struct NotchStripTests {

  /// A real cutout, measured: 220 × 38 on a 14" display.
  private let geometry = NotchGeometry(
    rect: CGRect(x: 790, y: 1131, width: 220, height: 38), isReal: true)

  private func settings(_ placement: NotchPlacement) -> NotchSettings {
    var settings = NotchSettings()
    settings.placement = placement
    // The model layer is read straight after `show`, so nothing may be in flight over it.
    settings.growMS = 0
    return settings
  }

  private func items(_ count: Int) -> [NotchItem] {
    (0..<count).map {
      NotchItem(appName: "App \($0)", badge: Badge(raw: "1"), color: .named(.red), style: .dot)
    }
  }

  /// The strip as `NotchWindow` builds it, hung in a host layer the size of that window — which
  /// is what lets an indicator's frame be read in the window's own coordinates.
  private func strip(_ placement: NotchPlacement, showing count: Int)
    -> (shape: CALayer, host: CALayer, settings: NotchSettings)
  {
    let settings = settings(placement)
    let size = NotchWindow.frame(for: geometry, settings: settings).size
    let strip = NotchStrip(geometry: geometry, settings: settings, size: size)
    let host = CALayer()
    host.frame = CGRect(origin: .zero, size: size)
    host.addSublayer(strip.shape)
    strip.show(
      NotchLayout(items: items(count), settings: settings), turn: nil, icons: IconCache())
    return (strip.shape, host, settings)
  }

  @Test(
    "an indicator is placed from the cutout, not from the shape's middle",
    arguments: NotchPlacement.allCases)
  func packedAgainstTheCutout(_ placement: NotchPlacement) throws {
    let (shape, host, settings) = strip(placement, showing: 4)
    // The window is built centred on the cutout, so its middle is the cutout's.
    let middle = Double(host.bounds.midX)
    let half = Double(geometry.rect.width) / 2
    let frames = (shape.sublayers ?? []).map { host.convert($0.frame, from: shape) }

    if placement != .right {
      let edges = frames.map { Double($0.maxX) }.filter { $0 <= middle }
      #expect(try #require(edges.max()) == middle - half - settings.gap)
    }
    if placement != .left {
      let edges = frames.map { Double($0.minX) }.filter { $0 >= middle }
      #expect(try #require(edges.min()) == middle + half + settings.gap)
    }
  }

  @Test("`mirror` puts every indicator at the reflection of its own position")
  func mirrored() {
    let (shape, host, _) = strip(.mirror, showing: 4)
    let middle = Double(host.bounds.midX)
    let centres = (shape.sublayers ?? []).map { Double(host.convert($0.frame, from: shape).midX) }
    let left = centres.filter { $0 < middle }.sorted().map { middle - $0 }
    let right = centres.filter { $0 > middle }.sorted().map { $0 - middle }
    #expect(left.count == 4)
    // Both read outward-in, so the outermost on the left pairs with the outermost on the right.
    #expect(left == right.reversed())
  }

  @Test(
    "the shape opens wide enough to show every indicator in it",
    arguments: NotchPlacement.allCases)
  func nothingIsClipped(_ placement: NotchPlacement) {
    let (shape, _, _) = strip(placement, showing: 4)
    let indicators = shape.sublayers ?? []
    // `mirror` draws each of them twice, once per extension.
    #expect(indicators.count == (placement == .mirror ? 8 : 4))
    // `masksToBounds` is on, so an indicator outside these bounds is one the user never sees.
    for indicator in indicators {
      #expect(shape.bounds.contains(indicator.frame))
    }
  }
}
