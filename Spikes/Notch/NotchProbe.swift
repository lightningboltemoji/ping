// NotchProbe.swift — what AppKit will tell us about a screen's notch.
//
//   swift Spikes/Notch/NotchProbe.swift
//
// Every number a fake notch needs has to come from public API (PRINCIPLES.md §2: no private
// symbols). This prints what is on offer, per screen, and derives the notch rect from it.

import AppKit

func f(_ r: NSRect) -> String {
  String(format: "x=%.1f y=%.1f w=%.1f h=%.1f", r.origin.x, r.origin.y, r.width, r.height)
}

_ = NSApplication.shared

for (i, s) in NSScreen.screens.enumerated() {
  let main = s == NSScreen.main ? "  ← NSScreen.main" : ""
  print("── screen \(i): \(s.localizedName)\(main)")
  print("   frame            \(f(s.frame))")
  print("   visibleFrame     \(f(s.visibleFrame))")
  print("   backingScale     \(s.backingScaleFactor)")
  print(
    "   safeAreaInsets   top=\(s.safeAreaInsets.top) left=\(s.safeAreaInsets.left) "
      + "bottom=\(s.safeAreaInsets.bottom) right=\(s.safeAreaInsets.right)")
  print("   auxTopLeftArea   \(s.auxiliaryTopLeftArea.map(f) ?? "nil")")
  print("   auxTopRightArea  \(s.auxiliaryTopRightArea.map(f) ?? "nil")")

  // The notch is the gap between the two auxiliary areas. Both are nil on a screen with no
  // notch and both are present on one that has it — so their absence is the test, and the
  // width is a subtraction rather than a guess.
  if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
    let notch = NSRect(
      x: l.maxX, y: s.frame.maxY - s.safeAreaInsets.top,
      width: r.minX - l.maxX, height: s.safeAreaInsets.top)
    print("   ⇒ notch rect     \(f(notch))")
  } else {
    // Menu bar height, for a screen that has to be told where its notch would be.
    let menuBar = s.frame.maxY - s.visibleFrame.maxY
    print("   ⇒ no notch; menu bar strip is \(menuBar)pt tall")
  }
  print("")
}
