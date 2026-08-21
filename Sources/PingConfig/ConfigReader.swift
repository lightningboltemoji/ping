//
//  ConfigReader.swift
//  PingConfig
//
//  Reading is *taking*: each model pulls the keys it knows out of its table and then asks
//  what is left. Whatever is left is a key the schema does not know, reported by line. There
//  is exactly one list of known keys and it is this file.
//

/// A config, and anything worth saying about how it was spelled.
public struct ParsedConfig: Equatable, Sendable {
  public var config: Config
  public var diagnostics: [ConfigDiagnostic]

  public init(config: Config, diagnostics: [ConfigDiagnostic] = []) {
    self.config = config
    self.diagnostics = diagnostics
  }
}

extension Config {
  /// An absent file and an empty file mean the same thing, so there is no separate
  /// "empty" path here — an empty document simply takes every default.
  public static func parse(_ text: String) throws -> ParsedConfig {
    var table = ConfigTable(root: try TOMLTable.parse(text))
    let config = try Config(reading: &table)
    return ParsedConfig(config: config, diagnostics: table.diagnostics)
  }
}

extension Config: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()

    general.pollIntervalMS =
      try table.takeInt("poll-interval-ms", in: 100...2000) ?? general.pollIntervalMS
    general.monitors = try table.takeEnum("monitors", as: Monitors.self) ?? general.monitors
    general.suppressWhenFocused =
      try table.takeBool("suppress-when-focused") ?? general.suppressWhenFocused
    general.launchAtLogin = try table.takeBool("launch-at-login") ?? general.launchAtLogin

    if var glowTable = try table.takeTable("glow") {
      glow = try GlowSettings(reading: &glowTable)
    }
    if var shelfTable = try table.takeTable("shelf") {
      shelf = try ShelfSettings(reading: &shelfTable)
    }
    if var notchTable = try table.takeTable("notch") {
      notch = try NotchSettings(reading: &notchTable)
    }

    // The apps tree is read bespoke rather than through the enumerable settings table:
    // its middle segment is a name the user invented.
    apps = try table.takeTables(under: "apps").map { name, appTable in
      var appTable = appTable
      return try AppConfig(name: name, reading: &appTable)
    }

    try table.reportUnknownKeys()
  }
}

extension GlowLayer: ConfigModel {
  /// The same five keys are legal at `[glow]`, at `apps.X.glow` and at
  /// `apps.X.glow.{count,dot}`, which is what makes the cascade uniform.
  public init(reading table: inout ConfigTable) throws {
    self.init()
    enabled = try table.takeBool("enabled")
    edge = try table.takeEnum("edge", as: Edge.self)
    color = try table.takeColor("color")
    size = try table.takeDouble("size", in: 0.25...1.0)
    opacity = try table.takeDouble("opacity", in: 0.0...1.0)
    try table.reportUnknownKeys()
  }
}

extension GlowSettings: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()
    if var pulseTable = try table.takeTable("pulse") {
      pulse = try PulseSettings(reading: &pulseTable)
    }
    defaults = try GlowLayer(reading: &table)
  }
}

extension PulseSettings: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()
    durationMS = try table.takeInt("duration-ms", in: 100...60_000) ?? durationMS
    minOpacity = try table.takeDouble("min-opacity", in: 0.0...1.0) ?? minOpacity
    maxOpacity = try table.takeDouble("max-opacity", in: 0.0...1.0) ?? maxOpacity
    crossfadeMS = try table.takeInt("crossfade-ms", in: 0...5_000) ?? crossfadeMS
    guard minOpacity <= maxOpacity else {
      throw ConfigSyntaxError(
        line: table.line,
        message: "'glow.pulse.min-opacity' must not be above 'glow.pulse.max-opacity'")
    }
    try table.reportUnknownKeys()
  }
}

extension ShelfSettings: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()
    enabled = try table.takeBool("enabled") ?? enabled
    anchor = try table.takeEnum("anchor", as: ShelfAnchor.self) ?? anchor
    margin = try table.takeDouble("margin", in: 0...500) ?? margin
    padding = try table.takeDouble("padding", in: 0...200) ?? padding
    iconSize = try table.takeDouble("icon-size", in: 8...256) ?? iconSize
    opacity = try table.takeDouble("opacity", in: 0.0...1.0) ?? opacity
    tint = try table.takeColor("tint") ?? tint
    showNames = try table.takeBool("show-names") ?? showNames
    showBadges = try table.takeBool("show-badges") ?? showBadges
    try table.reportUnknownKeys()
  }
}

extension AppConfig {
  init(name: String, reading table: inout ConfigTable) throws {
    self.init(name: name)
    bundleID = try table.takeString("bundle-id")
    if var glowTable = try table.takeTable("glow") {
      glow = try AppGlow(reading: &glowTable)
    }
    if var shelfTable = try table.takeTable("shelf") {
      shelf = try AppShelf(reading: &shelfTable)
    }
    if var notchTable = try table.takeTable("notch") {
      notch = try AppNotch(reading: &notchTable)
    }
    try table.reportUnknownKeys()
  }
}

extension AppGlow: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()
    // Badge-kind tables come out first so the rest of the table is the app's own layer.
    if var countTable = try table.takeTable("count") {
      count = try GlowLayer(reading: &countTable)
    }
    if var dotTable = try table.takeTable("dot") {
      dot = try GlowLayer(reading: &dotTable)
    }
    base = try GlowLayer(reading: &table)
  }
}

extension NotchSettings: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()
    enabled = try table.takeBool("enabled") ?? enabled
    placement = try table.takeEnum("placement", as: NotchPlacement.self) ?? placement
    style = try table.takeEnum("style", as: NotchStyle.self) ?? style
    maxWidth = try table.takeDouble("max-width", in: 0...600) ?? maxWidth
    alwaysShow = try table.takeBool("always-show") ?? alwaysShow
    width = try table.takeDouble("width", in: 60...600) ?? width
    itemSize = try table.takeDouble("item-size", in: 2...32) ?? itemSize
    gap = try table.takeDouble("gap", in: 0...32) ?? gap
    growMS = try table.takeInt("grow-ms", in: 0...5_000) ?? growMS
    try table.reportUnknownKeys()
  }
}

extension AppShelf: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()
    enabled = try table.takeBool("enabled")
    try table.reportUnknownKeys()
  }
}

extension NotchLayer: ConfigModel {
  /// The same two keys are legal at `apps.X.notch` and at `apps.X.notch.{count,dot}`, which is
  /// what makes this cascade read like the glow's.
  public init(reading table: inout ConfigTable) throws {
    self.init()
    enabled = try table.takeBool("enabled")
    color = try table.takeColor("color")
    try table.reportUnknownKeys()
  }
}

extension AppNotch: ConfigModel {
  public init(reading table: inout ConfigTable) throws {
    self.init()
    // Badge-kind tables come out first so the rest of the table is the app's own layer.
    if var countTable = try table.takeTable("count") {
      count = try NotchLayer(reading: &countTable)
    }
    if var dotTable = try table.takeTable("dot") {
      dot = try NotchLayer(reading: &dotTable)
    }
    base = try NotchLayer(reading: &table)
  }
}
