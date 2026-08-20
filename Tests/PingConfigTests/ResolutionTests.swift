import Testing

@testable import PingConfig

/// The ⊕ cascade (IMPLEMENTATION.md §4):
///
///     effective = builtinDefaults ⊕ [glow] ⊕ apps.A.glow ⊕ apps.A.glow.<kind>
@Suite("Cascade")
struct ResolutionTests {

  private func config(_ text: String) throws -> Config {
    try Config.parse(text).config
  }

  private func glow(_ text: String, _ app: String, _ kind: BadgeKind) throws -> ResolvedGlow? {
    try config(text).resolvedGlow(forAppNamed: app, badge: kind)
  }

  @Test("an app that writes `{}` takes every built-in default")
  func emptyTableTakesDefaults() throws {
    let resolved = try #require(try glow("[apps.Slack]\nglow = {}", "Slack", .count))
    #expect(resolved == ResolvedGlow.builtin)
  }

  @Test("`[glow]` moves the default for every subscribed app")
  func globalDefaults() throws {
    let text = """
      [glow]
      edge  = "top"
      color = "blue"

      [apps.Slack]
      glow = {}
      """
    let resolved = try #require(try glow(text, "Slack", .count))
    #expect(resolved.edge == .top)
    #expect(resolved.color == .named(.blue))
    #expect(resolved.size == 1.0)  // untouched keys still inherit the built-in
  }

  @Test("the app wins over the global, key by key")
  func appOverridesGlobal() throws {
    let text = """
      [glow]
      edge  = "top"
      color = "blue"
      size  = 0.5

      [apps.Slack]
      glow = { color = "#611f69" }
      """
    let resolved = try #require(try glow(text, "Slack", .count))
    #expect(resolved.color == PingColor("#611f69"))
    #expect(resolved.edge == .top)
    #expect(resolved.size == 0.5)
  }

  @Test("a badge kind wins over the app, and only for that kind")
  func badgeKindOverridesApp() throws {
    let text = """
      [apps.Messages.glow]
      color = "green"

      [apps.Messages.glow.dot]
      color = "red"
      """
    #expect(try glow(text, "Messages", .dot)?.color == .named(.red))
    #expect(try glow(text, "Messages", .count)?.color == .named(.green))
  }

  @Test("`enabled = false` under a badge kind silences only that kind")
  func badgeKindOptOut() throws {
    let text = """
      [apps.Messages.glow]
      color = "green"

      [apps.Messages.glow.dot]
      enabled = false
      """
    #expect(try glow(text, "Messages", .dot) == nil)
    #expect(try glow(text, "Messages", .count) != nil)
  }

  @Test("an app that never writes the effect does not get it")
  func presenceIsOptIn() throws {
    let text = """
      [glow]
      color = "blue"

      [apps.Mail]
      shelf = {}
      """
    #expect(try glow(text, "Mail", .count) == nil)
  }

  @Test("an app the file never mentions does not get it either")
  func unknownAppIsSilent() throws {
    #expect(try glow("[apps.Slack]\nglow = {}", "Mail", .count) == nil)
  }

  @Test("`[glow].enabled = false` is a master switch an app cannot talk its way past")
  func masterSwitch() throws {
    let text = """
      [glow]
      enabled = false

      [apps.Slack]
      glow = { enabled = true }
      """
    #expect(try glow(text, "Slack", .count) == nil)
    #expect(try glow(text, "Slack", .dot) == nil)
  }

  @Test("`enabled = false` on an app disables it without throwing away its settings")
  func disabledAppKeepsItsColor() throws {
    let parsed = try config(
      """
      [apps.Slack]
      glow = { color = "#611f69", enabled = false }
      """)
    #expect(parsed.resolvedGlow(forAppNamed: "Slack", badge: .count) == nil)
    #expect(parsed.app(named: "Slack")?.glow?.base.color == PingColor("#611f69"))
  }

  @Test("the notch takes only `enabled` and `color` per app, and red when it says neither")
  func notchMembership() throws {
    let parsed = try config(
      """
      [apps.Slack]
      notch = { color = "#611f69" }

      [apps.Mail]
      notch = {}

      [apps.Notes]
      notch = { enabled = false }

      [apps.Reminders]
      glow = {}
      """)
    #expect(
      parsed.resolvedNotch(forAppNamed: "Slack", badge: .count)?.color == PingColor("#611f69"))
    #expect(parsed.resolvedNotch(forAppNamed: "Mail", badge: .count)?.color == .named(.red))
    // Subscribed and opted out, and never subscribed: two different sentences, one `nil`.
    #expect(parsed.resolvedNotch(forAppNamed: "Notes", badge: .count) == nil)
    #expect(parsed.resolvedNotch(forAppNamed: "Reminders", badge: .count) == nil)
    #expect(parsed.app(named: "Notes")?.notch?.enabled == false)
    #expect(parsed.app(named: "Reminders")?.notch == nil)
  }

  @Test("`[notch].enabled = false` empties the strip")
  func notchMasterSwitch() throws {
    let parsed = try config(
      """
      [notch]
      enabled = false

      [apps.Slack]
      notch = { enabled = true }
      """)
    #expect(parsed.resolvedNotch(forAppNamed: "Slack", badge: .count) == nil)
    #expect(parsed.resolvedNotch(forAppNamed: "Slack", badge: .dot) == nil)
  }

  @Test("`style = \"count\"` falls back to a dot for a badge that has no digits")
  func notchCountFallsBackToDot() throws {
    let parsed = try config(
      """
      [notch]
      style = "count"

      [apps.Slack]
      notch = {}
      """)
    #expect(parsed.resolvedNotch(forAppNamed: "Slack", badge: .count)?.style == .count)
    #expect(parsed.resolvedNotch(forAppNamed: "Slack", badge: .dot)?.style == .dot)
  }

  @Test("the shelf takes only `enabled` per app")
  func shelfMembership() throws {
    let parsed = try config(
      """
      [apps.Slack]
      shelf = {}

      [apps.Mail]
      shelf = { enabled = false }

      [apps.Notes]
      glow = {}
      """)
    #expect(parsed.shelfShows(parsed.app(named: "Slack")!))
    #expect(!parsed.shelfShows(parsed.app(named: "Mail")!))
    #expect(!parsed.shelfShows(parsed.app(named: "Notes")!))
  }

  @Test("`[shelf].enabled = false` empties the bar")
  func shelfMasterSwitch() throws {
    let parsed = try config(
      """
      [shelf]
      enabled = false

      [apps.Slack]
      shelf = {}
      """)
    #expect(!parsed.shelfShows(parsed.app(named: "Slack")!))
  }

  @Test("the whole truth table, one badge kind at a time")
  func truthTable() throws {
    let text = """
      [glow]
      edge = "top"

      [apps.A]
      glow = {}

      [apps.B]
      glow = { edge = "left" }

      [apps.C.glow]
      edge = "right"

      [apps.C.glow.dot]
      edge = "bottom"

      [apps.D]
      shelf = {}
      """
    let expected: [(String, BadgeKind, Edge?)] = [
      ("A", .count, .top), ("A", .dot, .top),
      ("B", .count, .left), ("B", .dot, .left),
      ("C", .count, .right), ("C", .dot, .bottom),
      ("D", .count, nil), ("D", .dot, nil),
    ]
    let parsed = try config(text)
    for (app, kind, edge) in expected {
      #expect(
        parsed.resolvedGlow(forAppNamed: app, badge: kind)?.edge == edge,
        "\(app) with a \(kind.rawValue) badge")
    }
  }
}
