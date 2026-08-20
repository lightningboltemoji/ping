//
//  NotchLayout.swift
//  PingCore
//
//  Where the indicators go, as arithmetic: capacity, the two extensions, and what becomes of a
//  tail that does not fit. Pure and framework-free, so the policy is testable headless and the
//  renderer is left with nothing to decide but pixels and time.
//

import PingConfig

/// One extension of the strip. Not `NotchPlacement`: `split` is an instruction, not a side.
public enum NotchSide: String, CaseIterable, Sendable {
  case left, right
}

public struct NotchLayout: Equatable, Sendable {

  /// The indicators with a slot of their own, in file order — so reading the strip left to
  /// right reads the file.
  public let left: [NotchItem]
  public let right: [NotchItem]

  /// The tail that does not fit, taking turns in the last slot of `overflowSide` rather than
  /// being dropped: a strip that under-reported what is badged would be lying about the Dock.
  /// Contention resolved in time rather than in space, as two glows on one edge already are.
  public let overflow: [NotchItem]
  public let overflowSide: NotchSide?

  /// Points added to each side. A side carrying nothing stays at zero; with `split` both take
  /// the wider one's, so an odd number of indicators does not tip the notch to one side.
  public let leftWidth: Double
  public let rightWidth: Double

  public func items(on side: NotchSide) -> [NotchItem] {
    side == .left ? left : right
  }

  public func width(of side: NotchSide) -> Double {
    side == .left ? leftWidth : rightWidth
  }

  /// How many slots a side holds — its own indicators, plus one for the tail if it lands here.
  public func slots(on side: NotchSide) -> Int {
    items(on: side).count + (overflowSide == side ? 1 : 0)
  }

  public init(items: [NotchItem], settings: NotchSettings) {
    // A side wide enough for n indicators is gap · item · gap · item … gap, which makes capacity
    // the largest n that still fits the budget `max-width` sets.
    let pitch = settings.itemSize + settings.gap
    let width = { (n: Int) in n == 0 ? 0 : settings.gap + Double(n) * pitch }
    let capacity =
      pitch > 0 ? max(Int(((settings.maxWidth - settings.gap) / pitch).rounded(.down)), 0) : 0
    let slots = settings.placement == .split ? capacity * 2 : capacity

    guard slots > 0 else {
      self.init(left: [], right: [], overflow: [], overflowSide: nil, leftWidth: 0, rightWidth: 0)
      return
    }

    // Everything fits, or every slot but the last is spoken for and the rest share that one.
    let fits = items.count <= slots
    let placed = fits ? items : Array(items.prefix(slots - 1))
    let overflow = fits ? [] : Array(items.dropFirst(slots - 1))

    let left: [NotchItem]
    let right: [NotchItem]
    switch settings.placement {
    case .left:
      (left, right) = (placed, [])
    case .right:
      (left, right) = ([], placed)
    case .split:
      // Halved in file order rather than alternated: reading L-R-L-R across a cutout is not
      // reading a list. An odd one goes left, which is where the list starts.
      let half = (placed.count + 1) / 2
      (left, right) = (Array(placed.prefix(half)), Array(placed.dropFirst(half)))
    }

    // The tail takes turns in the last slot of the side the list ends in.
    let overflowSide: NotchSide? =
      overflow.isEmpty ? nil : (settings.placement == .left ? .left : .right)
    let leftSlots = left.count + (overflowSide == .left ? 1 : 0)
    let rightSlots = right.count + (overflowSide == .right ? 1 : 0)

    switch settings.placement {
    case .left:
      self.init(
        left: left, right: right, overflow: overflow, overflowSide: overflowSide,
        leftWidth: width(leftSlots), rightWidth: 0)
    case .right:
      self.init(
        left: left, right: right, overflow: overflow, overflowSide: overflowSide,
        leftWidth: 0, rightWidth: width(rightSlots))
    case .split:
      let both = width(max(leftSlots, rightSlots))
      self.init(
        left: left, right: right, overflow: overflow, overflowSide: overflowSide,
        leftWidth: both, rightWidth: both)
    }
  }

  private init(
    left: [NotchItem], right: [NotchItem], overflow: [NotchItem], overflowSide: NotchSide?,
    leftWidth: Double, rightWidth: Double
  ) {
    self.left = left
    self.right = right
    self.overflow = overflow
    self.overflowSide = overflowSide
    self.leftWidth = leftWidth
    self.rightWidth = rightWidth
  }
}
