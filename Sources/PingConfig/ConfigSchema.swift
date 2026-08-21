//
//  ConfigSchema.swift
//  PingConfig
//
//  The schema as a table you can enumerate, rather than one that exists only by being run.
//
//  Three consumers come off the one list — the settings window lays itself out from it, `ping
//  explain` prints it, and `ConfigDocument.set(_ setting:to:)` uses it to know that writing a
//  default means taking the line out.
//
//  **Presentation metadata belongs on the entry.** A section, an order, an advanced-or-not are
//  facts about the setting rather than about SwiftUI, and the alternative is a second list
//  drifting from this one. What stays out is anything a *frame* needs: no colours, no widths, no
//  view types, and nothing here imports a framework.
//
//  **What the table deliberately does not describe is `apps.*`** — the one open tree, whose middle
//  segment is a Dock title the user invents and which carries a cascade rather than a value. It
//  is read by `ConfigReader.swift` and edited by a panel written for it. Forcing it in
//  here would produce a worse table and a worse window both.
//
//  **The reader is still hand-written** rather than running this table. Ping's cascade means
//  the same five glow keys are read at four different depths, which a flat table cannot say. So the
//  two lists are pinned together by a test instead: every entry here is written into a document,
//  read back through the real reader, and has to arrive as the field it claims.
//

/// One setting the config file may carry: how it is spelled, what it means, what a legal value is,
/// and how that value crosses between the file and a `Config` field.
public struct Setting: Sendable {

  /// The key, spelled the way the file spells it: `glow.pulse.duration-ms`.
  public let key: TOMLKey
  /// The setting's name in prose, or on a control's label.
  public let label: String
  /// One sentence: what it does. Printed by `explain` and shown beside the control — two readers,
  /// so it stays a sentence.
  public let help: String
  /// What a legal value is, in the terms a diagnostic and a control both need.
  public let kind: Kind
  /// Which group it belongs to — the order a window shows them in.
  public let section: Section
  /// A dial rather than a preference: behind a disclosure, not on the main surface.
  public let isAdvanced: Bool

  /// The two halves of the setting's access to `Config`, kept as closures because the table is one
  /// array and the values it moves are of different types.
  private let render: @Sendable (Config) -> TOMLValue
  let apply: @Sendable (TOMLValue, inout Config) throws -> Void

  /// This setting's value in `config`, spelled as the file spells it — what `ConfigDocument.set`
  /// takes, and what a control shows.
  public func value(in config: Config) -> TOMLValue { render(config) }

  /// What this setting is when the file says nothing about it.
  public var defaultValue: TOMLValue { render(Config()) }

  /// Whether `config` leaves this setting alone.
  public func isDefault(in config: Config) -> Bool { isDefault(render(config)) }

  /// Whether writing `value` down would only repeat what Ping already does — in which case the
  /// line comes out instead, because a file that says the default pins it against ever changing.
  public func isDefault(_ value: TOMLValue) -> Bool {
    value.spelled == defaultValue.spelled
  }

  /// A key that is one `Config` field, moved by a codec.
  init<Value>(
    _ key: TOMLKey, _ field: WritableKeyPath<Config, Value> & Sendable, _ codec: Codec<Value>,
    label: String, help: String, section: Section, advanced: Bool = false
  ) {
    self.init(
      key, codec, label: label, help: help, section: section, advanced: advanced,
      get: { $0[keyPath: field] },
      set: { $0[keyPath: field] = $1 })
  }

  /// The general case: a key whose field is not quite the value.
  ///
  /// **What the `[glow]` defaults need.** `GlowLayer.edge` is an `Edge?` because `nil` is how
  /// "inherit" is spelled, and there is no such thing as a control for absence. So the
  /// getter answers the built-in the cascade starts from and the setter writes the option — which
  /// makes `defaultValue` the built-in, and so makes choosing it take the line back out.
  init<Value>(
    _ key: TOMLKey, _ codec: Codec<Value>, label: String, help: String, section: Section,
    advanced: Bool = false,
    get: @escaping @Sendable (Config) -> Value,
    set: @escaping @Sendable (inout Config, Value) -> Void
  ) {
    self.key = key
    self.label = label
    self.help = help
    self.kind = codec.kind
    self.section = section
    self.isAdvanced = advanced
    self.render = { codec.write(get($0)) }
    self.apply = { value, config in set(&config, try codec.read(value, key)) }
  }
}

extension Setting {

  /// What a legal value is. **One case per shape of control, never per setting** — a case serving
  /// a single key is the sign the table has stopped paying for itself.
  public enum Kind: Equatable, Sendable {
    /// `true` or `false`.
    case toggle
    /// A number, with the range it lives in and the unit it is counted in.
    case number(Bound, unit: Unit)
    /// One word from a fixed vocabulary, listed as the file spells them.
    case choice([String])
    /// A colour name or a hex triple — a colour well.
    case color
  }

  /// A number's range. A range rather than a bare floor, because every number Ping has is bounded
  /// at both ends — which is also what a slider needs to exist at all.
  public struct Bound: Equatable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double
    /// Whether the number is counted in whole units. A poll interval of 250.5ms is not a thing.
    public let isIntegral: Bool

    init(_ range: ClosedRange<Double>, isIntegral: Bool = false) {
      self.lowerBound = range.lowerBound
      self.upperBound = range.upperBound
      self.isIntegral = isIntegral
    }

    var range: ClosedRange<Double> { lowerBound...upperBound }

    /// The clause a value outside the range produces, and the one `explain` prints.
    public var requirement: String {
      let spell = { TOMLValue.spell($0, decimal: !isIntegral) }
      return "must be between \(spell(lowerBound)) and \(spell(upperBound))"
    }
  }

  /// What a number counts — the suffix beside a control, and a clause of `explain`'s sentence.
  public enum Unit: String, Equatable, Sendable {
    case points = "px"
    case milliseconds = "ms"
    /// A ratio: a number that counts nothing.
    case bare = ""
  }

  /// The groups a settings window shows, in the order it shows them.
  ///
  /// `apps` carries no *settings* on purpose — it is the surface the table cannot describe, and
  /// naming it here is what keeps a window's list of tabs one list rather than "the schema's,
  /// plus one".
  public enum Section: String, CaseIterable, Sendable {
    case general, glow, shelf, notch, apps

    public var title: String {
      switch self {
      case .general: "General"
      case .glow: "Glow"
      case .shelf: "Shelf"
      case .notch: "Notch"
      case .apps: "Apps"
      }
    }
  }

  /// What a legal value is, in one line: the sentence `explain` prints. Derived from the kind, so
  /// a new bound or a new enum case says so for free.
  public var legend: String? {
    switch kind {
    case .toggle:
      nil
    case .number(let bound, let unit):
      unit == .bare ? bound.requirement : "\(bound.requirement), in \(unit.name)"
    case .choice(let words):
      "one of " + words.map { "\"\($0)\"" }.joined(separator: ", ")
    case .color:
      "a color name (\(NamedColor.allCases.map(\.rawValue).joined(separator: ", "))) "
        + "or \"#rrggbb\" / \"#rrggbbaa\""
    }
  }

  /// The `[table]` the key is written under — everything before its last segment. What groups a
  /// panel's rows: a section spanning two tables is one the tab's own title cannot describe.
  public var table: TOMLKey {
    TOMLKey(key.segments.dropLast())
  }

  /// The key as it is written *inside* its table, which is the only part a line carries.
  public var name: String { key.segments.last ?? "" }
}

extension Setting.Unit {
  var name: String {
    switch self {
    case .points: "points"
    case .milliseconds: "milliseconds"
    case .bare: ""
    }
  }
}

//
// What makes one entry serve a control and a diagnostic both: a codec knows what a legal value is,
// how to take one out of the file and how to put one back. Every read goes through `ConfigTable`'s
// typed readers rather than restating them, so a value a slider produced and a value a line carried
// are refused with the same sentence.

struct Codec<Value: Sendable>: Sendable {
  /// What a legal value is. Handed to the entry, so the control and the diagnostic are built from
  /// one description rather than from two that agree today.
  let kind: Setting.Kind
  /// Validate a value the file carried, or a control produced. `key` only names it in a complaint.
  let read: @Sendable (TOMLValue, TOMLKey) throws -> Value
  let write: @Sendable (Value) -> TOMLValue
}

extension Codec where Value == Bool {
  static var toggle: Codec {
    Codec(kind: .toggle, read: { try $0.bool($1) }, write: { .bool($0) })
  }
}

extension Codec where Value == Double {
  static func number(_ range: ClosedRange<Double>, _ unit: Setting.Unit) -> Codec {
    let bound = Setting.Bound(range)
    return Codec(
      kind: .number(bound, unit: unit),
      read: { try $0.number($1, in: bound.range) },
      write: { .number($0) })
  }
}

extension Codec where Value == Int {
  /// A count. Bounded at both ends and whole, which is what separates a poll interval from a ratio.
  static func count(_ range: ClosedRange<Int>, _ unit: Setting.Unit) -> Codec {
    let bound = Setting.Bound(Double(range.lowerBound)...Double(range.upperBound), isIntegral: true)
    return Codec(
      kind: .number(bound, unit: unit),
      read: { try $0.integer($1, in: range) },
      write: { .number(Double($0)) })
  }
}

extension Codec where Value: RawRepresentable & CaseIterable, Value.RawValue == String {
  /// One word from a fixed vocabulary. **The type is the vocabulary**, so a case added to the enum
  /// is accepted, named in the diagnostic and offered by a control with nothing here to update.
  static var word: Codec {
    Codec(
      kind: .choice(Value.allCases.map(\.rawValue)),
      read: { try $0.word($1, as: Value.self) },
      write: { .string($0.rawValue) })
  }
}

extension Codec where Value == PingColor {
  static var color: Codec {
    Codec(kind: .color, read: { try $0.color($1) }, write: { .string($0.written) })
  }
}

//
// The table.

extension Setting {

  /// Every setting the file may carry, in the order a window shows them.
  public static let all: [Setting] = general + glow + shelf + notch

  /// The settings in one section, ordered as written.
  public static func all(in section: Section) -> [Setting] {
    all.filter { $0.section == section }
  }

  /// The setting a key names, or `nil` for one the table does not describe — every `apps.*` key.
  public static func setting(for key: TOMLKey) -> Setting? {
    all.first { $0.key == key }
  }

  private static let general: [Setting] = [
    Setting(
      ["poll-interval-ms"], \.general.pollIntervalMS, .count(100...2000, .milliseconds),
      label: "Poll interval",
      help: "How often the Dock is read for badges.",
      section: .general),
    Setting(
      ["monitors"], \.general.monitors, .word,
      label: "Monitors",
      help: "Whether an effect is drawn on the main screen or on every screen.",
      section: .general),
    Setting(
      ["suppress-when-focused"], \.general.suppressWhenFocused, .toggle,
      label: "Suppress when focused",
      help: "No effect for the app you are already looking at.",
      section: .general),
    Setting(
      ["launch-at-login"], \.general.launchAtLogin, .toggle,
      label: "Launch at login",
      help: "Start Ping when you log in.",
      section: .general),
  ]

  // The five glow keys are the *defaults* every app inherits, so each reads through the
  // built-in the cascade starts from rather than through the option the file stores.
  private static let glow: [Setting] = [
    Setting(
      ["glow", "enabled"], .toggle,
      label: "Enabled",
      help: "The master switch for the whole effect, whatever the apps say.",
      section: .glow,
      get: { $0.glow.defaults.enabled ?? ResolvedGlow.builtin.enabled },
      set: { $0.glow.defaults.enabled = $1 }),
    Setting(
      ["glow", "edge"], Codec<Edge>.word,
      label: "Edge",
      help: "Which screen edge the gradient bleeds in from.",
      section: .glow,
      get: { $0.glow.defaults.edge ?? ResolvedGlow.builtin.edge },
      set: { $0.glow.defaults.edge = $1 }),
    Setting(
      ["glow", "color"], .color,
      label: "Color",
      help: "The gradient's color, for apps that do not name one of their own.",
      section: .glow,
      get: { $0.glow.defaults.color ?? ResolvedGlow.builtin.color },
      set: { $0.glow.defaults.color = $1 }),
    Setting(
      ["glow", "size"], .number(0.25...1.0, .bare),
      label: "Size",
      help: "How far across the screen the gradient reaches.",
      section: .glow,
      get: { $0.glow.defaults.size ?? ResolvedGlow.builtin.size },
      set: { $0.glow.defaults.size = $1 }),
    Setting(
      ["glow", "opacity"], .number(0.0...1.0, .bare),
      label: "Opacity",
      help: "How strong the gradient is at its brightest.",
      section: .glow,
      get: { $0.glow.defaults.opacity ?? ResolvedGlow.builtin.opacity },
      set: { $0.glow.defaults.opacity = $1 }),
    Setting(
      ["glow", "pulse", "duration-ms"], \.glow.pulse.durationMS,
      .count(100...60_000, .milliseconds),
      label: "Pulse duration",
      help: "How long one breath of the pulse takes.",
      section: .glow, advanced: true),
    Setting(
      ["glow", "pulse", "min-opacity"], \.glow.pulse.minOpacity, .number(0.0...1.0, .bare),
      label: "Pulse minimum",
      help: "How far down the pulse breathes out.",
      section: .glow, advanced: true),
    Setting(
      ["glow", "pulse", "max-opacity"], \.glow.pulse.maxOpacity, .number(0.0...1.0, .bare),
      label: "Pulse maximum",
      help: "How far up the pulse breathes in.",
      section: .glow, advanced: true),
    Setting(
      ["glow", "pulse", "crossfade-ms"], \.glow.pulse.crossfadeMS, .count(0...5_000, .milliseconds),
      label: "Crossfade",
      help: "How long one app's glow takes to hand over when several share an edge.",
      section: .glow, advanced: true),
  ]

  private static let shelf: [Setting] = [
    Setting(
      ["shelf", "enabled"], \.shelf.enabled, .toggle,
      label: "Enabled",
      help: "The master switch for the shelf, whatever the apps say.",
      section: .shelf),
    Setting(
      ["shelf", "anchor"], \.shelf.anchor, .word,
      label: "Anchor",
      help: "Which corner or edge of the screen the bar sits against.",
      section: .shelf),
    Setting(
      ["shelf", "margin"], \.shelf.margin, .number(0...500, .points),
      label: "Margin",
      help: "How far the bar sits from the screen edge.",
      section: .shelf),
    Setting(
      ["shelf", "padding"], \.shelf.padding, .number(0...200, .points),
      label: "Padding",
      help: "How much room there is inside the bar, around the icons.",
      section: .shelf),
    Setting(
      ["shelf", "icon-size"], \.shelf.iconSize, .number(8...256, .points),
      label: "Icon size",
      help: "How large each app icon is drawn.",
      section: .shelf),
    Setting(
      ["shelf", "opacity"], \.shelf.opacity, .number(0.0...1.0, .bare),
      label: "Opacity",
      help: "How solid the bar is.",
      section: .shelf),
    Setting(
      ["shelf", "tint"], \.shelf.tint, .color,
      label: "Tint",
      help: "The bar's background color.",
      section: .shelf),
    Setting(
      ["shelf", "show-names"], \.shelf.showNames, .toggle,
      label: "Show names",
      help: "Whether each icon is captioned with its app's name.",
      section: .shelf),
    Setting(
      ["shelf", "show-badges"], \.shelf.showBadges, .toggle,
      label: "Show badges",
      help: "Whether each icon carries the badge the Dock is showing.",
      section: .shelf),
  ]

  private static let notch: [Setting] = [
    Setting(
      ["notch", "enabled"], \.notch.enabled, .toggle,
      label: "Enabled",
      help: "The master switch for the whole effect, whatever the apps say.",
      section: .notch),
    Setting(
      ["notch", "placement"], \.notch.placement, .word,
      label: "Placement",
      help: "Which side of the notch the indicators hang in.",
      section: .notch),
    Setting(
      ["notch", "style"], \.notch.style, .word,
      label: "Style",
      help: "What one indicator is drawn as.",
      section: .notch),
    Setting(
      ["notch", "max-width"], \.notch.maxWidth, .number(0...600, .points),
      label: "Maximum width",
      help: "How far the strip may grow on each side; past it the tail takes turns.",
      section: .notch),
    Setting(
      ["notch", "always-show"], \.notch.alwaysShow, .toggle,
      label: "Always show",
      help: "Whether a screen with no notch draws one even with nothing badged.",
      section: .notch),
    Setting(
      ["notch", "width"], \.notch.width, .number(60...600, .points),
      label: "Width",
      help: "How wide the stand-in notch is on a screen that has none.",
      section: .notch),
    Setting(
      ["notch", "item-size"], \.notch.itemSize, .number(2...32, .points),
      label: "Item size",
      help: "How large one indicator is drawn.",
      section: .notch, advanced: true),
    Setting(
      ["notch", "gap"], \.notch.gap, .number(0...32, .points),
      label: "Gap",
      help: "How much room there is between one indicator and the next.",
      section: .notch, advanced: true),
    Setting(
      ["notch", "grow-ms"], \.notch.growMS, .count(0...5_000, .milliseconds),
      label: "Grow duration",
      help: "How long the strip takes to open or close.",
      section: .notch, advanced: true),
  ]
}
