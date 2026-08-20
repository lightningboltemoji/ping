//
//  RenderState.swift
//  PingCore
//
//  One value describing everything that should be on screen. Renderers are dumb:
//  `func render(_ state: RenderState)`. Adding an effect later is one renderer and one
//  config section.
//

import Foundation
import PingConfig

public struct GlowInstance: Equatable, Sendable {
  public var appName: String
  public var glow: ResolvedGlow

  public init(appName: String, glow: ResolvedGlow) {
    self.appName = appName
    self.glow = glow
  }
}

public struct ShelfItem: Equatable, Sendable {
  public var appName: String
  public var badge: Badge
  public var appURL: URL?

  public init(appName: String, badge: Badge, appURL: URL? = nil) {
    self.appName = appName
    self.badge = badge
    self.appURL = appURL
  }
}

public struct ShelfState: Equatable, Sendable {
  public var settings: ShelfSettings
  public var items: [ShelfItem]

  public init(settings: ShelfSettings, items: [ShelfItem]) {
    self.settings = settings
    self.items = items
  }
}

/// One indicator in the notch. The badge and the app's location travel with it because the
/// style decides which is drawn: digits for `count`, the Dock icon for `icon`.
public struct NotchItem: Equatable, Sendable {
  public var appName: String
  public var badge: Badge
  public var color: PingColor
  public var style: NotchStyle
  public var appURL: URL?

  public init(
    appName: String, badge: Badge, color: PingColor, style: NotchStyle, appURL: URL? = nil
  ) {
    self.appName = appName
    self.badge = badge
    self.color = color
    self.style = style
    self.appURL = appURL
  }
}

/// The strip, and what is in it. Present with no items when `always-show` asks for the
/// stand-in on a screen that has no notch of its own.
public struct NotchState: Equatable, Sendable {
  public var settings: NotchSettings
  public var items: [NotchItem]

  public init(settings: NotchSettings, items: [NotchItem]) {
    self.settings = settings
    self.items = items
  }
}

public struct RenderState: Equatable, Sendable {
  public var glows: [GlowInstance] = []
  /// `nil` when the shelf should not be on screen at all.
  public var shelf: ShelfState?
  /// `nil` when the strip should not be on screen at all — which a renderer retracts to
  /// rather than dropping, so the effect leaves the way it arrived.
  public var notch: NotchState?
  public var pulse = PulseSettings()
  public var monitors: Monitors = .main
  /// A preview answers to the settings window rather than to the Dock, so it is drawn on
  /// one screen whatever `monitors` says.
  public var isPreview = false

  public init() {}

  public var isEmpty: Bool { glows.isEmpty && shelf == nil && notch == nil }
}
