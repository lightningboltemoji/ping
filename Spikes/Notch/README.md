# Notch — a spike

Three scripts, each run on its own with `swift`. Nothing here is wired into Ping; the question is
only whether a notch effect is available to build.

| Script                 | Answers                                                              |
| ---------------------- | -------------------------------------------------------------------- |
| `NotchProbe.swift`     | what a screen will tell us about its notch, and what it will not      |
| `NotchDemo.swift`      | one static shape over the menu bar, at a window level of your choosing |
| `NotchGrow.swift`      | the extension growing and shrinking, without resizing the window      |
| `FullscreenProbe.swift`| a stand-in "app you were working in", to take a full-screen space      |

```
swift Spikes/Notch/NotchProbe.swift
swift Spikes/Notch/NotchDemo.swift ext=160 radius=11 notch=210 debug=1
swift Spikes/Notch/NotchGrow.swift period=4 cycles=3
```

## Settled

- **The geometry is public API.** `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are both `nil` on
  a screen with no notch and both present on one that has it, so their absence is the test; the notch
  rect is the gap between them, `safeAreaInsets.top` tall. On a 14" MacBook Pro that is **185×32** at
  x=663.5, in a 1512×982 frame. A screen without one has to be told how wide its stand-in is, and its
  strip is `frame.maxY - visibleFrame.maxY` — 30pt on a Studio Display at 2560×1440.
- **The strip is not the menu bar.** On the built-in display `frame.maxY - visibleFrame.maxY` is 33
  and `safeAreaInsets.top` is 32: a real notch matches the cutout, a stand-in matches the menu bar.
- **Corner radius 10**, against the real cutout. There is no public API for the notch's own —
  `NSScreen._cornerRadius` is private, which §2 of `PRINCIPLES.md` rules out — so it stays a value
  with a good default.
- **The level floor is `.statusBar` (25).** At `.mainMenu` (24), `.floating` and `.normal` the menu
  bar's *text* composites above the window. 25 is what `ShelfWindow` already uses.
- **Black on a transparent menu bar is a false positive.** macOS 27 draws no menu bar background, so a
  black strip over an empty stretch of it looks identical whether it is above or below the menu bar,
  and menu titles under it disappear either way — dark text on black. `debug=1` tints the extensions,
  which is the only way the two cases separate.
- **The effect belongs to the screen.** `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` at
  `.statusBar` keeps the shape on top of a full-screen app on its own space (`FullscreenProbe`).
- **Growth is one layer, not a window resize.** The window is created at its widest and never moves;
  a `CALayer` with `cornerRadius` and `maskedCorners` set to the two bottom corners animates its
  `bounds.size.width` from the centre. `contentsScale` has to be the screen's, or the corners
  rasterise at 1× and read as steps.
- **Overriding `constrainFrameRect` buys nothing.** `constrain=1` hands the frame back to AppKit and
  the window sits in the menu bar strip regardless — borderless windows are not pushed out of it.

## Not settled

- **The extension covers, it does not reserve.** macOS reflows nothing around it: on the left it hides
  menu titles, on the right it hides other apps' status items, and in full-screen it covers app
  content rather than being letterboxed away from it. Clicks still land — `ignoresMouseEvents` — so
  what is hidden still works, invisibly. That is a design question, not a technical one.
