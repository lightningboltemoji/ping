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
  private var icons: [String: NSImage] = [:]
  private var geometry: (anchor: ShelfAnchor, margin: Double)?
  private var last = RenderState()

  public init() {}

  public func render(_ state: RenderState) {
    last = state

    guard let shelf = state.shelf else {
      hideAll()
      return
    }

    loadIcons(for: shelf.items)

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
      window.update(shelf: shelf, icons: icons)
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
    let window = ShelfWindow(shelf: shelf, icons: icons, screen: screen.visibleFrame)
    windows[screen.displayID] = window
    return window
  }

  private func loadIcons(for items: [ShelfItem]) {
    for item in items where icons[item.appName] == nil {
      guard let url = item.appURL else { continue }
      icons[item.appName] = NSWorkspace.shared.icon(forFile: url.path)
    }
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
