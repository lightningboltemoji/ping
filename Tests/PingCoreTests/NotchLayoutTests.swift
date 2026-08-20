import PingConfig
import Testing

@testable import PingCore

/// The arithmetic behind the strip: how many indicators a budget pays for, which extension each
/// goes in, and what becomes of the ones that do not fit.
///
/// The defaults are the working example throughout — `item-size` 8 and `gap` 8 make a slot 16
/// points wide, so `max-width` 120 pays for seven per side.
@Suite("Notch layout")
struct NotchLayoutTests {

  private func settings(
    placement: NotchPlacement = .split, maxWidth: Double = 120, itemSize: Double = 8,
    gap: Double = 8
  ) -> NotchSettings {
    var settings = NotchSettings()
    settings.placement = placement
    settings.maxWidth = maxWidth
    settings.itemSize = itemSize
    settings.gap = gap
    return settings
  }

  private func items(_ count: Int) -> [NotchItem] {
    (0..<count).map {
      NotchItem(appName: "App \($0)", badge: Badge(raw: "1"), color: .named(.red), style: .dot)
    }
  }

  private func names(_ items: [NotchItem]) -> [String] { items.map(\.appName) }

  @Test("a side is as wide as the indicators in it, up to the budget")
  func capacity() {
    let seven = NotchLayout(items: items(7), settings: settings(placement: .left))
    #expect(names(seven.left) == names(items(7)))
    #expect(seven.overflow.isEmpty)
    // gap · item · gap · item … gap — seven slots is exactly the 120 points on offer.
    #expect(seven.leftWidth == 120)

    let three = NotchLayout(items: items(3), settings: settings(placement: .left))
    #expect(three.leftWidth == 8 + 3 * 16)
  }

  @Test("the side nothing goes in does not widen")
  func placement() {
    let left = NotchLayout(items: items(3), settings: settings(placement: .left))
    #expect(names(left.left) == names(items(3)))
    #expect(left.right.isEmpty)
    #expect(left.rightWidth == 0)

    let right = NotchLayout(items: items(3), settings: settings(placement: .right))
    #expect(names(right.right) == names(items(3)))
    #expect(right.left.isEmpty)
    #expect(right.leftWidth == 0)
  }

  @Test("`split` halves the list in file order, and both sides take the wider one's width")
  func split() {
    let layout = NotchLayout(items: items(3), settings: settings())
    #expect(names(layout.left) == ["App 0", "App 1"])
    #expect(names(layout.right) == ["App 2"])
    // An odd number would otherwise produce a lopsided notch.
    #expect(layout.leftWidth == layout.rightWidth)
    #expect(layout.leftWidth == 8 + 2 * 16)
  }

  @Test("the tail takes turns in the last slot rather than being dropped")
  func overflowIsTheTail() {
    let layout = NotchLayout(items: items(10), settings: settings(placement: .left))
    // Six keep a slot of their own; the last of the seven is shared by the rest.
    #expect(names(layout.left) == names(items(6)))
    #expect(names(layout.overflow) == ["App 6", "App 7", "App 8", "App 9"])
    #expect(layout.overflowSide == .left)
    #expect(layout.slots(on: .left) == 7)
    #expect(layout.leftWidth == 120)
  }

  @Test("with `split` the tail lands in the side the list ends in")
  func overflowUnderSplit() {
    let layout = NotchLayout(items: items(20), settings: settings())
    #expect(layout.left.count == 7)
    #expect(layout.right.count == 6)
    #expect(names(layout.overflow) == names(items(20).suffix(7)))
    #expect(layout.overflowSide == .right)
    #expect(layout.slots(on: .left) == layout.slots(on: .right))
    #expect(layout.leftWidth == layout.rightWidth)
  }

  @Test("nothing badged is a strip at rest, not a strip of nothing")
  func empty() {
    let layout = NotchLayout(items: [], settings: settings())
    #expect(layout.left.isEmpty)
    #expect(layout.right.isEmpty)
    #expect(layout.overflowSide == nil)
    #expect(layout.leftWidth == 0)
    #expect(layout.rightWidth == 0)
  }

  @Test("a budget that pays for no slot at all shows no indicator")
  func noRoom() {
    let layout = NotchLayout(items: items(3), settings: settings(maxWidth: 0))
    #expect(layout.left.isEmpty)
    #expect(layout.right.isEmpty)
    #expect(layout.overflow.isEmpty)
    #expect(layout.leftWidth == 0)
  }

  @Test("a bigger indicator fits fewer of them")
  func itemSizeMovesCapacity() {
    let layout = NotchLayout(items: items(6), settings: settings(placement: .left, itemSize: 24))
    #expect(layout.left.count == 2)  // (120 - 8) / 32 = 3 slots, the last one shared
    #expect(layout.overflow.count == 4)
    #expect(layout.leftWidth == 8 + 3 * 32)
  }
}
