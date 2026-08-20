import Testing

@testable import PingConfig

@Suite("Schema")
struct ConfigReaderTests {

  @Test("an absent file and an empty file mean the same thing")
  func emptyIsDefaults() throws {
    #expect(try Config.parse("").config == Config())
    #expect(try Config.parse("\n# nothing here\n").config == Config())
  }

  @Test("the globals")
  func globals() throws {
    let config = try Config.parse(
      """
      poll-interval-ms      = 250
      monitors              = "all"
      suppress-when-focused = true
      launch-at-login       = true
      """
    ).config
    #expect(config.general.pollIntervalMS == 250)
    #expect(config.general.monitors == .all)
    #expect(config.general.suppressWhenFocused)
    #expect(config.general.launchAtLogin)
  }

  @Test("an unknown key is an error naming its line")
  func unknownKey() {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try Config.parse(
        """
        poll-interval-ms = 500

        [glow]
        colour = "green"
        """)
    }
    #expect(error?.line == 4)
    #expect(error?.message == "unknown key 'glow.colour'")
  }

  @Test("an unknown key deep in the apps tree is named in full")
  func unknownKeyUnderApp() {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try Config.parse(
        """
        [apps.Slack]
        glow = { color = "green", shade = "dark" }
        """)
    }
    #expect(error?.message == "unknown key 'apps.Slack.glow.shade'")
  }

  @Test("a whole unknown table is an error too")
  func unknownTable() {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try Config.parse(
        """
        [line]
        position = "bottom"
        """)
    }
    // The header, not the first key under it: a table the schema never heard of is one mistake on
    // line 1, and naming `line.position` would suggest the table were fine and the key the typo.
    #expect(error == ConfigSyntaxError(line: 1, message: "unknown key 'line'"))
  }

  @Test("a number outside its range is refused with the bound in the message")
  func rangeRefused() {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try Config.parse("[glow]\nsize = 0.1")
    }
    #expect(error?.message == "'glow.size' must be between 0.25 and 1.0, got 0.1")

    let interval = #expect(throws: ConfigSyntaxError.self) {
      try Config.parse("poll-interval-ms = 50")
    }
    #expect(interval?.message == "'poll-interval-ms' must be between 100 and 2000, got 50")
  }

  @Test("a value of the wrong type says which type it wanted")
  func typeMismatch() {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try Config.parse("suppress-when-focused = 1")
    }
    #expect(error?.message == "'suppress-when-focused' expects a boolean, got an integer")
  }

  @Test("camelCase enum values are accepted with a diagnostic naming the new spelling")
  func camelCaseLeniency() throws {
    let parsed = try Config.parse("[shelf]\nanchor = \"topCenter\"")
    #expect(parsed.config.shelf.anchor == .topCenter)
    #expect(parsed.diagnostics.count == 1)
    #expect(parsed.diagnostics[0].line == 2)
    #expect(
      parsed.diagnostics[0].message == "'shelf.anchor' should be \"top-center\", not \"topCenter\"")
  }

  @Test("an enum value that is simply wrong lists what it could have been")
  func unknownEnumValue() {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try Config.parse("[glow]\nedge = \"middle\"")
    }
    #expect(error?.message.contains("\"top\", \"bottom\", \"left\", \"right\"") == true)
  }

  @Test("colors are named or hex")
  func colors() throws {
    let config = try Config.parse(
      """
      [apps.Slack]
      glow = { color = "#611f69" }

      [apps.Mail]
      glow = { color = "blue" }

      [apps.Notes]
      glow = { color = "#ff000080" }
      """
    ).config
    #expect(config.app(named: "Slack")?.glow?.base.color == PingColor("#611f69"))
    #expect(config.app(named: "Mail")?.glow?.base.color == .named(.blue))
    let translucent = try #require(config.app(named: "Notes")?.glow?.base.color)
    #expect(abs(translucent.rgba.alpha - 128.0 / 255.0) < 0.001)
    #expect(translucent.rgba.red == 1.0)
  }

  @Test("a color that is neither is refused")
  func badColor() {
    #expect(throws: ConfigSyntaxError.self) {
      try Config.parse("[glow]\ncolor = \"chartreuse\"")
    }
    #expect(throws: ConfigSyntaxError.self) {
      try Config.parse("[glow]\ncolor = \"#12345\"")
    }
  }

  @Test("writing an effect under an app subscribes it; absence does not")
  func subscriptionIsPresence() throws {
    let config = try Config.parse(
      """
      [apps.Slack]
      glow = {}
      shelf = {}

      [apps.Mail]
      shelf = {}
      """
    ).config
    #expect(config.app(named: "Slack")?.glow != nil)
    #expect(config.app(named: "Slack")?.shelf != nil)
    #expect(config.app(named: "Mail")?.glow == nil)
    #expect(config.app(named: "Mail")?.shelf != nil)
  }

  @Test("apps keep the order the file introduces them in")
  func appOrder() throws {
    let config = try Config.parse(
      """
      [apps.Zed]
      glow = {}

      [apps.Alacritty]
      glow = {}

      [apps."Google Chrome"]
      glow = {}
      """
    ).config
    #expect(config.apps.map(\.name) == ["Zed", "Alacritty", "Google Chrome"])
  }

  @Test("badge-kind overrides read in long form")
  func badgeKindTables() throws {
    let config = try Config.parse(
      """
      [apps.Messages.glow]
      color = "green"

      [apps.Messages.glow.dot]
      enabled = false

      [apps.Messages.glow.count]
      color = "red"
      """
    ).config
    let glow = try #require(config.app(named: "Messages")?.glow)
    #expect(glow.base.color == .named(.green))
    #expect(glow.dot?.enabled == false)
    #expect(glow.count?.color == .named(.red))
  }

  @Test("a bare badge-kind table still subscribes the app to the effect")
  func implicitSubscription() throws {
    let config = try Config.parse(
      """
      [apps.Messages.glow.dot]
      enabled = false
      """
    ).config
    #expect(config.app(named: "Messages")?.glow != nil)
  }

  @Test("the pulse table")
  func pulse() throws {
    let config = try Config.parse(
      """
      [glow.pulse]
      duration-ms  = 1500
      min-opacity  = 0.1
      max-opacity  = 0.8
      crossfade-ms = 250
      """
    ).config
    #expect(config.glow.pulse.durationMS == 1500)
    #expect(config.glow.pulse.minOpacity == 0.1)
    #expect(config.glow.pulse.maxOpacity == 0.8)
    #expect(config.glow.pulse.crossfadeMS == 250)
  }

  @Test("a pulse that breathes backwards is refused")
  func inversePulse() {
    #expect(throws: ConfigSyntaxError.self) {
      try Config.parse("[glow.pulse]\nmin-opacity = 0.9\nmax-opacity = 0.2")
    }
  }

  @Test("bundle-id reads, and is optional")
  func bundleID() throws {
    let config = try Config.parse(
      """
      [apps.Slack]
      bundle-id = "com.tinyspeck.slackmacgap"
      glow = {}
      """
    ).config
    #expect(config.app(named: "Slack")?.bundleID == "com.tinyspeck.slackmacgap")
  }

  @Test("an integer is a legal spelling of a float")
  func integerAsFloat() throws {
    let config = try Config.parse("[shelf]\nmargin = 20").config
    #expect(config.shelf.margin == 20)
  }
}
