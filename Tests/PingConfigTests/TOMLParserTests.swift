import Testing

@testable import PingConfig

/// Properties of the grammar itself, and the conformance corpus the parser under it has to satisfy.
///
/// These were written against a placeholder that read the subset Ping's schema uses; the parser is
/// now a whole TOML 1.0.0 one, so the cases that pinned what the stand-in *refused* are now cases
/// pinning that the grammar reads them and leaves the schema to have the opinion.
@Suite("TOML grammar")
struct TOMLParserTests {

  private func parse(_ text: String) throws -> ConfigTable {
    ConfigTable(root: try TOMLTable.parse(text))
  }

  /// Walk into a nested table the way the schema does, so a test says what a reader would see.
  private func table(_ table: ConfigTable, _ path: String...) throws -> ConfigTable {
    var cursor = table
    for name in path {
      cursor = try #require(try cursor.takeTable(name), "no table at '\(name)'")
    }
    return cursor
  }

  @Test("an empty document is a table with nothing in it")
  func emptyDocument() throws {
    #expect(try parse("").isEmpty)
    #expect(try parse("# just a comment\n\n").isEmpty)
    #expect(try parse("\u{FEFF}# a byte-order mark is not a key\n").isEmpty)
  }

  @Test("`{}` registers a declared table, which is how presence is opt-in")
  func emptyInlineTableIsDeclared() throws {
    let glow = try table(try parse("[apps.Slack]\nglow = {}"), "apps", "Slack", "glow")
    #expect(glow.isEmpty)
  }

  @Test("an inline table flattens to the same keys a header would produce")
  func inlineFlattensLikeHeader() throws {
    for text in [
      "[apps.Slack]\nglow = { color = \"blue\", edge = \"left\" }",
      "[apps.Slack.glow]\ncolor = \"blue\"\nedge = \"left\"",
      "apps.Slack.glow = { color = \"blue\", edge = \"left\" }",
      "[apps.Slack]\nglow.color = \"blue\"\nglow.edge = \"left\"",
    ] {
      var glow = try table(try parse(text), "apps", "Slack", "glow")
      #expect(try glow.takeColor("color") == .named(.blue))
      #expect(try glow.takeEnum("edge", as: Edge.self) == .left)
      try glow.reportUnknownKeys()
    }
  }

  @Test("nested inline tables")
  func nestedInline() throws {
    var pulse = try table(try parse(#"glow = { pulse = { duration-ms = 100 } }"#), "glow", "pulse")
    #expect(try pulse.takeInt("duration-ms") == 100)
  }

  @Test("an inline table cannot be reopened by a later header")
  func inlineCannotBeExtended() {
    #expect(throws: ConfigSyntaxError.self) {
      try TOMLTable.parse(
        """
        [apps.Messages]
        glow = { color = "green" }

        [apps.Messages.glow.dot]
        enabled = false
        """)
    }
  }

  @Test("an inline table beside an expanded header for a different key is fine")
  func inlineBesideHeader() throws {
    var messages = try table(
      try parse(
        """
        [apps.Messages]
        shelf = {}

        [apps.Messages.glow]
        color = "green"
        """), "apps", "Messages")
    #expect(try messages.takeTable("shelf") != nil)
    var glow = try #require(try messages.takeTable("glow"))
    #expect(try glow.takeColor("color") == .named(.green))
  }

  @Test("a comment cannot appear inside braces")
  func commentInsideBraces() {
    #expect(throws: ConfigSyntaxError.self) {
      try TOMLTable.parse(##"glow = { color = "blue" # hi }"##)
    }
  }

  @Test("unlike arrays, inline tables reject a trailing comma")
  func trailingComma() throws {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try TOMLTable.parse(#"glow = { color = "blue", }"#)
    }
    #expect(error?.message == "an inline table cannot end with a ','")
    // The array it is unlike.
    #expect(throws: Never.self) { try TOMLTable.parse("sizes = [1, 2, ]") }
  }

  @Test("an inline table must open and close on one line")
  func inlineIsOneLine() {
    #expect(throws: ConfigSyntaxError.self) {
      try TOMLTable.parse("glow = {\n  color = \"blue\"\n}")
    }
  }

  @Test("a duplicate table header is refused")
  func duplicateHeader() {
    #expect(throws: ConfigSyntaxError.self) {
      try TOMLTable.parse("[apps.Slack]\n[apps.Slack]")
    }
  }

  @Test("a deeper header implies the tables above it, which may still be written later")
  func impliedThenDeclared() throws {
    var apps = try table(try parse("[apps.Slack.glow]\ncolor = \"blue\"\n\n[apps]\n"), "apps")
    #expect(try apps.takeTable("Slack") != nil)
  }

  @Test("a duplicate key is refused")
  func duplicateKey() throws {
    let error = #expect(throws: ConfigSyntaxError.self) {
      try TOMLTable.parse("poll-interval-ms = 100\npoll-interval-ms = 200")
    }
    #expect(error?.message == "'poll-interval-ms' is set twice")
  }

  @Test("quoted table keys keep spaces and dots to themselves")
  func quotedKeys() throws {
    var apps = try table(try parse("[apps.\"Google Chrome\"]\nglow = {}"), "apps")
    #expect(try apps.takeTable("Google Chrome") != nil)
  }

  /// The reason paths are `TOMLKey` rather than dotted strings: the middle segment of an
  /// `apps` path is a Dock title, and a Dock title may contain a `.`.
  @Test("an app named with a dot in it is one app, not a nesting")
  func dottedAppName() throws {
    var root = try parse("[apps.\"Node.js\"]\nglow = { color = \"green\" }")
    let apps = root.takeTables(under: "apps")
    #expect(apps.map(\.name) == ["Node.js"])
    var slack = apps[0].table
    var glow = try #require(try slack.takeTable("glow"))
    #expect(try glow.takeColor("color") == .named(.green))
  }

  @Test("errors name the line they happened on")
  func errorsCarryLines() {
    #expect(throws: ConfigSyntaxError(line: 3, message: "expected 'key = value'")) {
      try TOMLTable.parse(
        """
        [glow]
        color = "green"
        edge
        """)
    }
  }

  @Test("CRLF is read the same as LF")
  func crlf() throws {
    var lf = try table(try parse("[glow]\ncolor = \"green\"\n"), "glow")
    var crlf = try table(try parse("[glow]\r\ncolor = \"green\"\r\n"), "glow")
    #expect(try lf.takeColor("color") == .named(.green))
    #expect(try crlf.takeColor("color") == .named(.green))
  }

  /// The placeholder refused these rather than mis-read them. The real grammar reads them, and it
  /// is the schema that has the opinion — every one of these is an unknown key, not bad TOML.
  @Test(
    "TOML the schema has no use for still parses",
    arguments: [
      "apps = [1, 2]",
      "[[window-rules]]\napp-id = 'x'",
      "when = 1979-05-27",
      "when = 1979-05-27T07:32:00Z",
      "when = 07:32:00",
      "note = \"\"\"long\nnote\"\"\"",
      "pattern = 'no \\escapes here'",
      "size = 0x2A",
      "big = 1_000_000",
      "ratio = 6.02e23",
    ])
  func realTOMLParses(text: String) throws {
    #expect(throws: Never.self) { try TOMLTable.parse(text) }
    #expect(throws: ConfigSyntaxError.self) { try Config.parse(text) }
  }

  @Test("a bad date is refused as a date rather than read as something else")
  func badDate() {
    #expect(throws: ConfigSyntaxError.self) { try TOMLTable.parse("when = 1979-02-30") }
  }

  @Test("leftovers are reported earliest line first, so the complaint names the first mistake")
  func leftoversByLine() throws {
    var root = try parse(
      """
      [shelf]
      tint = "white"
      colour = "green"
      wrong = 1
      """)
    var shelf = try #require(try root.takeTable("shelf"))
    _ = try shelf.takeColor("tint")
    let error = #expect(throws: ConfigSyntaxError.self) { try shelf.reportUnknownKeys() }
    #expect(error == ConfigSyntaxError(line: 3, message: "unknown key 'shelf.colour'"))
  }
}
