//
//  ShelfRenderer.swift
//  PingUI
//
//  What used to be `FloatingDockController` and its six observation loops.
//

import AppKit
import PingConfig
import PingCore

@MainActor
public final class ShelfRenderer {

  private var windows: [CGDirectDisplayID: ShelfWindow] = [:]
  private let icons = IconCache.shared
  private var geometry: (anchor: ShelfAnchor, margin: Double)?
  private var last = RenderState()

  public init() {}

  public func render(_ state: RenderState) {
    last = state

    guard let shelf = state.shelf else {
      hideAll()
      return
    }

    for item in shelf.items { icons.load(item.appName, from: item.appURL) }

    // Anchor and margin are baked into the window frame, so a change to either means new
    // windows rather than new contents.
    let wanted = (anchor: shelf.settings.anchor, margin: shelf.settings.margin)
    if let geometry, geometry != wanted {
      closeAll()
    }
    geometry = wanted

    let screens =
      state.isPreview
      ? [NSScreen.main].compactMap { $0 }
      : ScreenTopology.targetScreens(for: state.monitors)
    let targets = Set(screens.map(\.displayID))

    for screen in screens {
      let window = window(for: screen, shelf: shelf)
      window.update(shelf: shelf, icons: icons.images)
      window.orderFrontRegardless()
    }

    for (displayID, window) in windows where !targets.contains(displayID) {
      window.orderOut(nil)
    }
  }

  public func screenParametersChanged() {
    closeAll()
    render(last)
  }

  private func window(for screen: NSScreen, shelf: ShelfState) -> ShelfWindow {
    if let existing = windows[screen.displayID] { return existing }
    let window = ShelfWindow(shelf: shelf, icons: icons.images, screen: screen.visibleFrame)
    windows[screen.displayID] = window
    return window
  }

  private func hideAll() {
    for (_, window) in windows {
      window.orderOut(nil)
    }
  }

  private func closeAll() {
    hideAll()
    windows.removeAll()
  }
}
