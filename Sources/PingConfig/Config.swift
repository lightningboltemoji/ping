//
//  Config.swift
//  PingConfig
//
//  The immutable value the whole app reads. Nothing here is observable and nothing here
//  changes: a new file produces a new `Config`. Anything that varies while
//  Ping runs — snooze, acknowledgement, what is frontmost — is `RuntimeState` in PingCore.
//

/// The seam `ConfigDocument<C>` attaches to: a model that can be read out of a
/// parsed table, and compared against the reading of an edited one.
public protocol ConfigModel: Equatable {
  init(reading table: inout ConfigTable) throws
}

public enum Monitors: String, CaseIterable, Sendable {
  case main, all
}

public enum Edge: String, CaseIterable, Sendable {
  case top, bottom, left, right
}

public enum ShelfAnchor: String, CaseIterable, Sendable {
  case topLeft = "top-left"
  case topCenter = "top-center"
  case topRight = "top-right"
  case bottomLeft = "bottom-left"
  case bottomCenter = "bottom-center"
  case bottomRight = "bottom-right"

  public var isTop: Bool {
    switch self {
    case .topLeft, .topCenter, .topRight: true
    case .bottomLeft, .bottomCenter, .bottomRight: false
    }
  }
}

/// Which extension an app's indicator goes in, and therefore which side widens.
public enum NotchPlacement: String, CaseIterable, Sendable {
  case left, right, split
}

/// What one indicator is drawn as. Three, because that is the whole of Ping's alphabet
/// (`PRINCIPLES.md` §1): area, identity, and the count itself.
public enum NotchStyle: String, CaseIterable, Sendable {
  case dot, icon, count
}

/// What kind of badge the Dock is showing. `DockReader` returns `nil` for no badge,
/// `""` for a bare red dot and digits for a count.
public enum BadgeKind: String, CaseIterable, Sendable {
  case count, dot
}

public struct GeneralSettings: Equatable, Sendable {
  public var pollIntervalMS: Int = 500
  public var monitors: Monitors = .main
  public var suppressWhenFocused: Bool = false
  public var launchAtLogin: Bool = false

  public init() {}
}

/// One level of the glow cascade: every key optional, because absent means "inherit"
/// and that distinction is the whole of the cascade (IMPLEMENTATION.md §4).
public struct GlowLayer: Equatable, Sendable {
  public var enabled: Bool?
  public var edge: Edge?
  public var color: PingColor?
  public var size: Double?
  public var opacity: Double?

  public init() {}

  /// `self ⊕ other` — keys written in `other` win, keys absent from it inherit.
  public func overlaid(with other: GlowLayer) -> GlowLayer {
    var out = self
    if let v = other.enabled { out.enabled = v }
    if let v = other.edge { out.edge = v }
    if let v = other.color { out.color = v }
    if let v = other.size { out.size = v }
    if let v = other.opacity { out.opacity = v }
    return out
  }

  public var isEmpty: Bool {
    enabled == nil && edge == nil && color == nil && size == nil && opacity == nil
  }
}

/// A glow with every key answered — what a renderer is handed.
public struct ResolvedGlow: Equatable, Sendable {
  public var enabled: Bool
  public var edge: Edge
  public var color: PingColor
  public var size: Double
  public var opacity: Double

  /// The built-in defaults the cascade starts from.
  public static let builtin = ResolvedGlow(
    enabled: true, edge: .bottom, color: .named(.green), size: 1.0, opacity: 1.0)

  public init(enabled: Bool, edge: Edge, color: PingColor, size: Double, opacity: Double) {
    self.enabled = enabled
    self.edge = edge
    self.color = color
    self.size = size
    self.opacity = opacity
  }

  public func applying(_ layer: GlowLayer) -> ResolvedGlow {
    ResolvedGlow(
      enabled: layer.enabled ?? enabled,
      edge: layer.edge ?? edge,
      color: layer.color ?? color,
      size: layer.size ?? size,
      opacity: layer.opacity ?? opacity)
  }
}

/// The breathing animation. Global only — a per-app pulse would let two apps on one edge
/// breathe at different rates, which the rotator would then have to arbitrate.
public struct PulseSettings: Equatable, Sendable {
  public var durationMS: Int = 2000
  public var minOpacity: Double = 0.25
  public var maxOpacity: Double = 0.95
  public var crossfadeMS: Int = 400

  public init() {}
}

/// The `[glow]` table: the effect's defaults, plus its master switch.
public struct GlowSettings: Equatable, Sendable {
  public var defaults = GlowLayer()
  public var pulse = PulseSettings()

  public init() {}

  /// `[glow].enabled = false` turns the effect off wholesale, whatever the apps say.
  public var isEnabled: Bool { defaults.enabled != false }
}

public struct ShelfSettings: Equatable, Sendable {
  public var enabled: Bool = true
  public var anchor: ShelfAnchor = .topCenter
  public var margin: Double = 20
  public var padding: Double = 16
  public var iconSize: Double = 32
  public var opacity: Double = 0.8
  public var tint: PingColor = .named(.white)
  public var showNames: Bool = true
  public var showBadges: Bool = true

  public init() {}
}

/// The `[notch]` table: a black strip hanging from the top edge, the width of the notch plus an
/// extension either side, holding one indicator per badged app. On a screen with no notch of its
/// own it draws one.
public struct NotchSettings: Equatable, Sendable {
  public var enabled: Bool = true
  public var placement: NotchPlacement = .split
  public var style: NotchStyle = .dot
  /// Extra points per side. The extension covers what is under it rather than reserving room,
  /// so this is a budget: past it the tail takes turns in the last slot.
  public var maxWidth: Double = 120
  /// Whether a screen with no notch draws the stand-in with nothing badged. On a screen that
  /// has one this says nothing: the notch is already always there.
  public var alwaysShow: Bool = false
  /// The stand-in's own width. 185 is the 14" cutout exactly.
  public var width: Double = 185
  /// No public API answers for the real cutout's radius, so it is a value with a good default.
  public var cornerRadius: Double = 10
  public var itemSize: Double = 8
  public var gap: Double = 8
  public var growMS: Int = 350

  public init() {}
}

/// One indicator with every key answered — what a renderer is handed.
public struct ResolvedNotchItem: Equatable, Sendable {
  public var color: PingColor
  public var style: NotchStyle

  /// What an app that says only `notch = {}` is drawn in: the Dock badge's own red, so an
  /// indicator is legible without naming a colour.
  public static let defaultColor: PingColor = .named(.red)

  public init(color: PingColor, style: NotchStyle) {
    self.color = color
    self.style = style
  }
}

/// An app's glow subscription: what it overrides, and what each badge kind overrides
/// on top of that.
public struct AppGlow: Equatable, Sendable {
  public var base = GlowLayer()
  public var count: GlowLayer?
  public var dot: GlowLayer?

  public init() {}

  public func layer(for kind: BadgeKind) -> GlowLayer {
    let override = kind == .count ? count : dot
    return base.overlaid(with: override ?? GlowLayer())
  }
}

public struct AppShelf: Equatable, Sendable {
  public var enabled: Bool?

  public init(enabled: Bool? = nil) {
    self.enabled = enabled
  }
}

/// An app's notch subscription. Only these two: `style` is the strip's own, because indicators
/// disagreeing about their shape is the same mistake as a per-app shelf anchor.
public struct AppNotch: Equatable, Sendable {
  public var enabled: Bool?
  public var color: PingColor?

  public init(enabled: Bool? = nil, color: PingColor? = nil) {
    self.enabled = enabled
    self.color = color
  }
}

/// One `[apps.<DockTitle>]` block. An effect written under it is a subscription; an
/// effect absent from it means the app does not get that effect at all.
public struct AppConfig: Equatable, Sendable {
  public var name: String
  public var bundleID: String?
  public var glow: AppGlow?
  public var shelf: AppShelf?
  public var notch: AppNotch?

  public init(
    name: String, bundleID: String? = nil, glow: AppGlow? = nil, shelf: AppShelf? = nil,
    notch: AppNotch? = nil
  ) {
    self.name = name
    self.bundleID = bundleID
    self.glow = glow
    self.shelf = shelf
    self.notch = notch
  }
}

public struct Config: Equatable, Sendable {
  public var general = GeneralSettings()
  public var glow = GlowSettings()
  public var shelf = ShelfSettings()
  public var notch = NotchSettings()
  public var apps: [AppConfig] = []

  /// An absent file and an empty file mean the same thing: every default.
  public init() {}

  public func app(named name: String) -> AppConfig? {
    apps.first { $0.name == name }
  }
}

// MARK: - Resolution

extension Config {

  /// `builtinDefaults ⊕ [glow] ⊕ apps.A.glow ⊕ apps.A.glow.<kind>`, or `nil` when this
  /// app should not glow for this badge at all.
  public func resolvedGlow(for app: AppConfig, badge kind: BadgeKind) -> ResolvedGlow? {
    guard glow.isEnabled, let appGlow = app.glow else { return nil }
    let resolved = ResolvedGlow.builtin
      .applying(glow.defaults)
      .applying(appGlow.layer(for: kind))
    return resolved.enabled ? resolved : nil
  }

  public func resolvedGlow(forAppNamed name: String, badge kind: BadgeKind) -> ResolvedGlow? {
    guard let app = app(named: name) else { return nil }
    return resolvedGlow(for: app, badge: kind)
  }

  /// The shelf is one shared object, so per-app it takes only `enabled`.
  public func shelfShows(_ app: AppConfig) -> Bool {
    guard shelf.enabled, let appShelf = app.shelf else { return false }
    return appShelf.enabled ?? true
  }

  /// This app's indicator, or `nil` three ways: the master switch is off, the app never
  /// subscribed, or it subscribed and opted out. The style is the strip's, except that `count`
  /// has no digits to draw for a bare dot and falls back to one.
  public func resolvedNotch(for app: AppConfig, badge kind: BadgeKind) -> ResolvedNotchItem? {
    guard notch.enabled, let appNotch = app.notch, appNotch.enabled ?? true else { return nil }
    let style: NotchStyle = notch.style == .count && kind == .dot ? .dot : notch.style
    return ResolvedNotchItem(color: appNotch.color ?? ResolvedNotchItem.defaultColor, style: style)
  }

  public func resolvedNotch(forAppNamed name: String, badge kind: BadgeKind) -> ResolvedNotchItem? {
    guard let app = app(named: name) else { return nil }
    return resolvedNotch(for: app, badge: kind)
  }
}
