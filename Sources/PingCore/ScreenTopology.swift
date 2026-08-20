//
//  ScreenTopology.swift
//  PingCore
//
//  Which screens an effect belongs on, and when that answer changes — in one place, so
//  every renderer does not grow its own copy of the notification dance.
//

import AppKit
import PingConfig

extension NSScreen {
  public var displayID: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
  }
}

/// Where a screen's notch is, and whether it is the screen's own: the cutout, or where a stand-in
/// for one goes. A stand-in's strip is the menu bar's, which is not quite the cutout's height.
public struct NotchGeometry: Equatable, Sendable {
  public let rect: CGRect
  public let isReal: Bool

  public init(rect: CGRect, isReal: Bool) {
    self.rect = rect
    self.isReal = isReal
  }
}

@MainActor
public enum ScreenTopology {

  public static func targetScreens(for monitors: Monitors) -> [NSScreen] {
    switch monitors {
    case .main: [NSScreen.main].compactMap { $0 }
    case .all: NSScreen.screens
    }
  }

  /// The notch, measured. Both auxiliary areas are absent on a screen without one and present on
  /// a screen with it, so their absence is the test and the cutout is the gap between them. A
  /// screen without one is *told* how wide its stand-in is, because that number is the config's.
  public static func notch(of screen: NSScreen, standInWidth: Double) -> NotchGeometry {
    let frame = screen.frame
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
      let height = screen.safeAreaInsets.top
      return NotchGeometry(
        rect: CGRect(
          x: left.maxX, y: frame.maxY - height, width: right.minX - left.maxX, height: height),
        isReal: true)
    }
    // A screen that is not showing the menu bar has no strip of its own to measure, and still
    // has a top edge to hang one from.
    let strip = frame.maxY - screen.visibleFrame.maxY
    let height = strip > 0 ? strip : NSStatusBar.system.thickness
    return NotchGeometry(
      rect: CGRect(
        x: frame.midX - standInWidth / 2, y: frame.maxY - height,
        width: standInWidth, height: height),
      isReal: false)
  }

  /// Fires once per `didChangeScreenParameters` — a display arriving, leaving, or being
  /// rearranged. Renderers rebuild their windows on each element.
  public static func changes() -> AsyncStream<Void> {
    AsyncStream { continuation in
      let task = Task { @MainActor in
        let notifications = NotificationCenter.default.notifications(
          named: NSApplication.didChangeScreenParametersNotification)
        for await _ in notifications {
          continuation.yield(())
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
