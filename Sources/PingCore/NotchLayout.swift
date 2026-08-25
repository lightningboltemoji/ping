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

  /// The indicators with a slot of their own, in slot order — slots are packed against the cutout,
  /// so the left extension's last entry is the one beside it and the right extension's first one
  /// is. Under every placement but `mirror`, reading the strip left to right reads the file.
  public let left: [NotchItem]
  public let right: [NotchItem]

  /// The tail that does not fit, taking turns in one slot per side of `overflowSlots` rather than
  /// being dropped: a strip that under-reported what is badged would be lying about the Dock.
  /// Contention resolved in time rather than in space, as two glows on one edge already are.
  public let overflow: [NotchItem]

  /// Which sides hold a slot for the tail, and which slot — the end of that side's reading, which
  /// on a reflected right extension is the slot against the cutout rather than the outermost.
  public let overflowSlots: [NotchSide: Int]

  /// Points added to each side. A side carrying nothing stays at zero; with `split` and `mirror`
  /// both take the wider one's, so an odd number of indicators does not tip the notch.
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
    items(on: side).count + (overflowSlots[side] == nil ? 0 : 1)
  }

  /// What each slot of a side holds, in slot order. `nil` is the tail's slot, which is empty until
  /// one of them takes its turn in it.
  public func contents(on side: NotchSide) -> [NotchItem?] {
    var contents: [NotchItem?] = items(on: side)
    if let slot = overflowSlots[side] { contents.insert(nil, at: slot) }
    return contents
  }

  public init(items: [NotchItem], settings: NotchSettings) {
    // A side wide enough for n indicators is gap · item · gap · item … gap, which makes capacity
    // the largest n that still fits the budget `max-width` sets.
    let pitch = settings.itemSize + settings.gap
    let width = { (n: Int) in n == 0 ? 0 : settings.gap + Double(n) * pitch }
    let capacity =
      pitch > 0 ? max(Int(((settings.maxWidth - settings.gap) / pitch).rounded(.down)), 0) : 0
    // `split` spends the two budgets on one list; `mirror` spends them on two copies of it.
    let slots = settings.placement == .split ? capacity * 2 : capacity

    guard slots > 0 else {
      self.init(left: [], right: [], overflow: [], overflowSlots: [:], leftWidth: 0, rightWidth: 0)
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
    case .mirror:
      // The whole list on each side, the right one reflected: both extensions then read outward-in
      // and the strip has an axis of symmetry through the cutout, whatever is badged.
      (left, right) = (placed, placed.reversed())
    }

    // The tail takes turns in the last slot of the side the list ends in — which on a reflected
    // side is the slot against the cutout, so the two stay reflections while it changes hands.
    var overflowSlots: [NotchSide: Int] = [:]
    if !overflow.isEmpty {
      switch settings.placement {
      case .left: overflowSlots = [.left: left.count]
      case .right, .split: overflowSlots = [.right: right.count]
      case .mirror: overflowSlots = [.left: left.count, .right: 0]
      }
    }

    let leftSlots = left.count + (overflowSlots[.left] == nil ? 0 : 1)
    let rightSlots = right.count + (overflowSlots[.right] == nil ? 0 : 1)
    // A side nothing goes in is zero wide; the two that share a list open to the wider of them.
    let evened = settings.placement == .split || settings.placement == .mirror
    let both = width(max(leftSlots, rightSlots))
    self.init(
      left: left, right: right, overflow: overflow, overflowSlots: overflowSlots,
      leftWidth: evened ? both : width(leftSlots),
      rightWidth: evened ? both : width(rightSlots))
  }

  private init(
    left: [NotchItem], right: [NotchItem], overflow: [NotchItem],
    overflowSlots: [NotchSide: Int], leftWidth: Double, rightWidth: Double
  ) {
    self.left = left
    self.right = right
    self.overflow = overflow
    self.overflowSlots = overflowSlots
    self.leftWidth = leftWidth
    self.rightWidth = rightWidth
  }
}
