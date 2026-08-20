//
//  NotchLayer.swift
//  PingUI
//
//  The shape and its indicators. Core Animation rather than SwiftUI: the width morph is the whole
//  effect, and an `NSHostingView` would be fighting it for the one property that matters.
//
//  **`masksToBounds` is load-bearing.** An indicator that escaped the shape would be a coloured
//  dot loose on the menu bar; inside it, the closing strip eats its own contents.
//
//  The shape's bounds run from −(left extension + half the cutout) to +(right extension + half the
//  cutout), so x = 0 is the cutout's middle whichever side is opening. That is what lets the two
//  extensions differ: `bounds` and `position` move together, and an indicator stays where it was put.
//

import AppKit
import PingConfig
import PingCore

@MainActor
final class NotchLayer {

  /// The strip. Every indicator is a sublayer of it.
  let shape = CALayer()

  private let geometry: NotchGeometry
  private let settings: NotchSettings
  /// The notch's middle, in the window's own coordinates. The window is built centred on it.
  private let center: CGPoint
  private var indicators: [CALayer] = []

  var contentsScale: CGFloat = 2 {
    didSet {
      shape.contentsScale = contentsScale
      for indicator in indicators { indicator.contentsScale = contentsScale }
    }
  }

  init(geometry: NotchGeometry, settings: NotchSettings, size: CGSize) {
    self.geometry = geometry
    self.settings = settings
    self.center = CGPoint(x: size.width / 2, y: size.height / 2)

    shape.backgroundColor = NSColor.black.cgColor
    shape.cornerRadius = settings.cornerRadius
    // It hangs from the top edge, so only the bottom two corners are ever on screen.
    shape.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    shape.masksToBounds = true
    shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    shape.position = center
    shape.bounds = bounds(left: 0, right: 0)
  }

  /// Put the indicators in their slots and open the strip to fit them.
  func show(_ layout: NotchLayout, turn: NotchItem?, icons: IconCache) {
    place(layout, turn: turn, icons: icons)
    open(left: layout.leftWidth, right: layout.rightWidth)
  }

  /// Close it. A real notch stops at its own cutout; a stand-in goes back to nothing, so it
  /// never pops into existence at full width either.
  func retract() {
    open(left: 0, right: 0)
  }

  /// What the strip is when there is nothing to say: the cutout it grew out of, or none at all.
  private var restingWidth: Double {
    geometry.isReal ? geometry.rect.width : 0
  }

  /// The strip with its extensions open this far, in coordinates the notch's middle is the
  /// origin of. A closed strip is the cutout it grew out of, so that is what the sides open from.
  private func bounds(left: Double, right: Double) -> CGRect {
    let cutout = left + right > 0 ? geometry.rect.width : restingWidth
    return CGRect(
      x: -(cutout / 2 + left), y: -geometry.rect.height / 2,
      width: cutout + left + right, height: geometry.rect.height)
  }

  private func open(left: Double, right: Double) {
    let bounds = bounds(left: left, right: right)
    // The extensions can differ, so the shape's middle is not always the notch's.
    let position = CGPoint(x: center.x + (right - left) / 2, y: center.y)
    guard shape.bounds != bounds || shape.position != position else { return }

    CATransaction.begin()
    if settings.growMS > 0 {
      CATransaction.setAnimationDuration(Double(settings.growMS) / 1000)
      CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
    } else {
      CATransaction.setDisableActions(true)
    }
    shape.bounds = bounds
    shape.position = position
    CATransaction.commit()
  }

  /// The indicators do not animate: they are laid out where they belong and the opening strip
  /// reveals them, which is one motion on screen rather than two disagreeing about the same one.
  private func place(_ layout: NotchLayout, turn: NotchItem?, icons: IconCache) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for indicator in indicators { indicator.removeFromSuperlayer() }
    indicators = []

    for side in NotchSide.allCases {
      let slots = layout.slots(on: side)
      for (slot, item) in layout.items(on: side).enumerated() {
        add(item, at: slot, on: side, of: slots, icons: icons)
      }
      // The tail's slot is the last one, and whichever of them is currently taking a turn in it.
      if layout.overflowSide == side, let turn {
        add(turn, at: slots - 1, on: side, of: slots, icons: icons)
      }
    }
    CATransaction.commit()
  }

  private func add(
    _ item: NotchItem, at slot: Int, on side: NotchSide, of slots: Int, icons: IconCache
  ) {
    let indicator = layer(for: item, icons: icons)
    indicator.contentsScale = contentsScale
    indicator.position = CGPoint(x: x(of: slot, on: side, of: slots), y: 0)
    shape.addSublayer(indicator)
    indicators.append(indicator)
  }

  /// Slots are packed against the notch and counted in reading order, so the left extension's
  /// last slot is the one beside the cutout and the right extension's first one is.
  private func x(of slot: Int, on side: NotchSide, of slots: Int) -> Double {
    let pitch = settings.itemSize + settings.gap
    let inner = geometry.rect.width / 2 + settings.gap + settings.itemSize / 2
    switch side {
    case .left: return -(inner + Double(slots - 1 - slot) * pitch)
    case .right: return inner + Double(slot) * pitch
    }
  }

  private func layer(for item: NotchItem, icons: IconCache) -> CALayer {
    let size = settings.itemSize
    switch item.style {
    case .icon:
      // An app whose icon has not arrived yet still says something, in its own colour.
      guard let icon = icons[item.appName] else { return dot(item) }
      let layer = CALayer()
      layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
      layer.contents = icon
      layer.contentsGravity = .resizeAspect
      return layer

    case .count:
      // A count is drawn at `item-size` and may spill into the gaps around its slot: the slots
      // are uniform, and digits are not.
      let text = CATextLayer()
      let string = NSAttributedString(
        string: item.badge.raw,
        attributes: [.font: Self.font(size: size), .foregroundColor: item.color.nsColor])
      text.string = string
      text.alignmentMode = .center
      let measured = string.size()
      text.bounds = CGRect(
        x: 0, y: 0, width: measured.width.rounded(.up), height: measured.height.rounded(.up))
      return text

    case .dot:
      return dot(item)
    }
  }

  private func dot(_ item: NotchItem) -> CALayer {
    let dot = CALayer()
    dot.backgroundColor = item.color.nsColor.cgColor
    dot.bounds = CGRect(x: 0, y: 0, width: settings.itemSize, height: settings.itemSize)
    dot.cornerRadius = settings.itemSize / 2
    return dot
  }

  /// Chango, which the bundle already ships and the menu bar already writes `ping` in.
  private static func font(size: Double) -> NSFont {
    NSFont(name: "Chango", size: size) ?? .systemFont(ofSize: size, weight: .bold)
  }
}
