//
//  NotchRenderer.swift
//  PingUI
//
//  One window per display, the shelf's shape: a dictionary keyed by `displayID`, the last
//  `RenderState` kept, and a rebuild when the screens move.
//
//  The strip's geometry is baked into its window, so a change to any of `[notch]` closes the
//  windows and makes new ones rather than re-laying-out the old.
//

import AppKit
import PingConfig
import PingCore

@MainActor
public final class NotchRenderer {

  /// How long one app waits in the overflow slot before the next takes a turn. The strip's own
  /// motion is its arrival and its retraction, so this is the one clock it keeps.
  private static let turnInterval = Duration.seconds(3)

  private var windows: [CGDirectDisplayID: NotchWindow] = [:]
  private let icons = IconCache()
  private var settings: NotchSettings?
  private var rotator = Rotator<NotchItem>()
  private var turn: Task<Void, Never>?
  private var last = RenderState()

  public init() {}

  public func render(_ state: RenderState) {
    last = state

    // Absent means retract, not vanish: the strip leaves the way it arrived, and on a screen
    // with a real notch there is nothing to take away below the cutout.
    guard let notch = state.notch else {
      stopTurning()
      for (_, window) in windows { window.strip.retract() }
      return
    }

    if settings != notch.settings { closeAll() }
    settings = notch.settings

    for item in notch.items { icons.load(item.appName, from: item.appURL) }

    let layout = NotchLayout(items: notch.items, settings: notch.settings)
    rotator.setAvailable(layout.overflow)

    let screens =
      state.isPreview
      ? [NSScreen.main].compactMap { $0 }
      : ScreenTopology.targetScreens(for: state.monitors)
    let targets = Set(screens.map(\.displayID))

    for screen in screens {
      let window = window(for: screen, notch: notch)
      window.strip.show(layout, turn: rotator.current, icons: icons)
      window.orderFrontRegardless()
    }

    for (displayID, window) in windows where !targets.contains(displayID) {
      window.orderOut(nil)
    }

    keepTurning(layout.overflow.count > 1)
  }

  /// A display arrived, left, or moved: every window's geometry is stale.
  public func screenParametersChanged() {
    closeAll()
    render(last)
  }

  private func window(for screen: NSScreen, notch: NotchState) -> NotchWindow {
    if let existing = windows[screen.displayID] { return existing }
    let geometry = ScreenTopology.notch(of: screen, standInWidth: notch.settings.width)
    let window = NotchWindow(geometry: geometry, settings: notch.settings)
    windows[screen.displayID] = window
    return window
  }

  /// The overflow slot changes hands on its own clock, because nothing else here ticks: a badge
  /// that does not change produces no render at all.
  private func keepTurning(_ wanted: Bool) {
    guard wanted else {
      stopTurning()
      return
    }
    guard turn == nil else { return }
    turn = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.turnInterval)
        guard !Task.isCancelled, let self else { return }
        _ = rotator.next()
        render(last)
      }
    }
  }

  private func stopTurning() {
    turn?.cancel()
    turn = nil
  }

  private func closeAll() {
    for (_, window) in windows { window.orderOut(nil) }
    windows.removeAll()
  }
}
