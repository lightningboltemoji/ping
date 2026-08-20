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

public struct RenderState: Equatable, Sendable {
  public var glows: [GlowInstance] = []
  /// `nil` when the shelf should not be on screen at all.
  public var shelf: ShelfState?
  public var pulse = PulseSettings()
  public var monitors: Monitors = .main
  /// A preview answers to the settings window rather than to the Dock, so it is drawn on
  /// one screen whatever `monitors` says.
  public var isPreview = false

  public init() {}

  public var isEmpty: Bool { glows.isEmpty && shelf == nil }
}
