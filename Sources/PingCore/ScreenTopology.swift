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

@MainActor
public enum ScreenTopology {

  public static func targetScreens(for monitors: Monitors) -> [NSScreen] {
    switch monitors {
    case .main: [NSScreen.main].compactMap { $0 }
    case .all: NSScreen.screens
    }
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
