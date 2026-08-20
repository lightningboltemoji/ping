//
//  GlowRenderer.swift
//  PingUI
//
//  What used to be `GlowController` and its five `withObservationTracking` re-arm loops.
//  It is now dumb: hand it a `RenderState` and it makes the screen match.
//

import AppKit
import PingConfig
import PingCore

@MainActor
public final class GlowRenderer {

  private struct Key: Hashable {
    let displayID: CGDirectDisplayID
    let edge: Edge
  }

  private var windows: [Key: GlowWindow] = [:]
  private var last = RenderState()

  public init() {}

  public func render(_ state: RenderState) {
    last = state

    let byEdge = Dictionary(grouping: state.glows, by: { $0.glow.edge })
    // A preview answers to the settings window, which is on one screen.
    let screens =
      state.isPreview
      ? [NSScreen.main].compactMap { $0 }
      : ScreenTopology.targetScreens(for: state.monitors)

    var active: Set<Key> = []
    for screen in screens {
      for (edge, instances) in byEdge {
        let key = Key(displayID: screen.displayID, edge: edge)
        active.insert(key)
        let window = window(for: edge, on: screen)
        window.update(instances.map(\.glow), pulse: state.pulse)
        window.showGlow()
      }
    }

    for (key, window) in windows where !active.contains(key) {
      window.update([], pulse: state.pulse)
      window.hideGlow()
    }
  }

  /// A display arrived, left, or moved: every window's geometry is stale.
  public func screenParametersChanged() {
    for (_, window) in windows {
      window.orderOut(nil)
    }
    windows.removeAll()
    render(last)
  }

  private func window(for edge: Edge, on screen: NSScreen) -> GlowWindow {
    let key = Key(displayID: screen.displayID, edge: edge)
    if let existing = windows[key] { return existing }
    let window = GlowWindow(screen: screen, edge: edge)
    window.hideGlow()
    windows[key] = window
    return window
  }
}
