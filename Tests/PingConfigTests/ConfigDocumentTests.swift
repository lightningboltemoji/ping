import Testing

@testable import PingConfig

/// What an edit is allowed to do to a file somebody wrote by hand.
///
/// The corpus is Ping's own example config, because a property that holds for a page of comments,
/// blank lines, aligned `=` signs and both table forms holds for anything a settings window will
/// meet. Byte-for-byte round-tripping is structural — `rendered` is the stored text — so what these
/// pin is the other half: that an edit reaches exactly the stretch it names.
@Suite("Config document")
struct ConfigDocumentTests {

  private typealias Document = ConfigDocument<Config>

  private func document(_ text: String = ConfigExample.text) throws -> Document {
    try Document(text)
  }

  /// The lines that differ between two versions of a file, as `(before, after)` pairs. What "an
  /// edit changes exactly one line" is measured with.
  private func changedLines(_ before: String, _ after: String) -> [(String, String)] {
    let old = before.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    let new = after.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    guard old.count == new.count else { return [("<\(old.count) lines>", "<\(new.count) lines>")] }
    return zip(old, new).filter { $0 != $1 }.map { (String($0), String($1)) }
  }

  // MARK: - Reading

  @Test("a document renders back byte for byte")
  func roundTrip() throws {
    #expect(try document().rendered == ConfigExample.text)
    #expect(try document("").rendered == "")
    #expect(
      try document("[glow]\r\ncolor = \"green\"\r\n").rendered == "[glow]\r\ncolor = \"green\"\r\n")
  }

  @Test("a document reads what `Config.parse` reads, and throws what it throws")
  func agreesWithParse() throws {
    #expect(try document().config == Config.parse(ConfigExample.text).config)
    #expect(throws: ConfigSyntaxError.self) { try document("[glow]\ncolour = \"green\"\n") }
  }

  // MARK: - Setting a value

  @Test("setting a key the file already writes changes that line and no other byte")
  func setExisting() throws {
    var edited = try document()
    try edited.set(["glow", "color"], to: .string("blue"))
    #expect(edited.config.glow.defaults.color == .named(.blue))
    let changed = changedLines(ConfigExample.text, edited.rendered)
    #expect(changed.count == 1)
    // Down to the alignment and the trailing comment.
    #expect(
      changed.first?.1 == ##"color   = "blue"               # a name, or "#rrggbb" / "#rrggbbaa""##)
  }

  @Test("the same change written twice writes the same file")
  func deterministic() throws {
    var once = try document()
    try once.set(["shelf", "icon-size"], to: .number(48))
    var twice = try document()
    try twice.set(["shelf", "icon-size"], to: .number(48))
    #expect(once.rendered == twice.rendered)

    // And a key the file does not have yet lands in the same place both times.
    var addedOnce = try document()
    try addedOnce.set(["shelf", "margin"], to: .number(4))
    var addedTwice = try document()
    try addedTwice.set(["shelf", "margin"], to: .number(4))
    #expect(addedOnce.rendered == addedTwice.rendered)
  }

  @Test("a key the file has no line for joins the end of its table's run")
  func insertIntoHeader() throws {
    var edited = try document("[glow]\ncolor = \"green\"\n\n[shelf]\nopacity = 0.5\n")
    try edited.set(["glow", "edge"], to: .string("left"))
    #expect(
      edited.rendered == "[glow]\ncolor = \"green\"\nedge = \"left\"\n\n[shelf]\nopacity = 0.5\n")
  }

  @Test("a key whose table the file never wrote gets a header of its own")
  func insertNewHeader() throws {
    var edited = try document("poll-interval-ms = 250\n")
    try edited.set(["apps", "Slack", "glow", "color"], to: .string("#611f69"))
    #expect(
      edited.rendered == """
        poll-interval-ms = 250

        [apps.Slack.glow]
        color = "#611f69"

        """)
    #expect(edited.config.app(named: "Slack")?.glow?.base.color == PingColor("#611f69"))
  }

  @Test("a top-level key goes above the first header, because TOML says it must")
  func insertTopLevel() throws {
    var edited = try document("[glow]\ncolor = \"green\"\n")
    try edited.set(["poll-interval-ms"], to: .number(250))
    #expect(edited.rendered == "poll-interval-ms = 250\n\n[glow]\ncolor = \"green\"\n")
    #expect(edited.config.general.pollIntervalMS == 250)
  }

  @Test("an edit the schema refuses leaves the document exactly as it was")
  func refusedEditCostsNothing() throws {
    var edited = try document()
    #expect(throws: ConfigSyntaxError.self) {
      try edited.set(["glow", "size"], to: .number(9))
    }
    #expect(edited.rendered == ConfigExample.text)
  }

  @Test("a number keeps the type it is written as")
  func numberSpelling() throws {
    var edited = try document("[shelf]\nicon-size = 32\n")
    try edited.set(["shelf", "icon-size"], to: .number(48))
    #expect(edited.rendered == "[shelf]\nicon-size = 48\n")
    try edited.set(["shelf", "opacity"], to: .number(0.5))
    #expect(edited.rendered == "[shelf]\nicon-size = 48\nopacity = 0.5\n")
  }

  // MARK: - Inline tables

  @Test("editing a value inside braces changes one line and no other byte")
  func setInsideBraces() throws {
    var edited = try document()
    try edited.set(["apps", "Slack", "glow", "edge"], to: .string("right"))
    let changed = changedLines(ConfigExample.text, edited.rendered)
    #expect(changed.count == 1)
    #expect(changed.first?.1 == ##"glow  = { color = "#611f69", edge = "right" }"##)
    #expect(edited.config.app(named: "Slack")?.glow?.base.edge == .right)
  }

  @Test("adding and removing a pair round-trips")
  func pairRoundTrip() throws {
    let start = "[apps.Slack]\nglow = { color = \"blue\" }\n"
    var edited = try document(start)
    try edited.set(["apps", "Slack", "glow", "opacity"], to: .number(0.5))
    #expect(edited.rendered == "[apps.Slack]\nglow = { color = \"blue\", opacity = 0.5 }\n")
    try edited.remove(["apps", "Slack", "glow", "opacity"])
    #expect(edited.rendered == start)
  }

  @Test("removing the last pair leaves `{}` — the app is still subscribed")
  func removingLastPairLeavesEmptyTable() throws {
    var edited = try document("[apps.Slack]\nglow = { color = \"blue\" }  # purple, really\n")
    try edited.remove(["apps", "Slack", "glow", "color"])
    #expect(edited.rendered == "[apps.Slack]\nglow = {}  # purple, really\n")
    #expect(edited.config.app(named: "Slack")?.glow != nil)
  }

  @Test("a key below an inline table is written into it as a dotted pair")
  func insertBelowBraces() throws {
    var edited = try document("[apps.Messages]\nglow = { color = \"green\" }\n")
    try edited.set(["apps", "Messages", "glow", "dot", "enabled"], to: .bool(false))
    #expect(
      edited.rendered == "[apps.Messages]\nglow = { color = \"green\", dot.enabled = false }\n")
    #expect(edited.config.app(named: "Messages")?.glow?.dot?.enabled == false)
  }

  @Test("a nested inline table is the one the pair belongs to")
  func nestedBraces() throws {
    var edited = try document(
      "[apps.Messages]\nglow = { color = \"green\", dot = { enabled = false } }\n")
    try edited.set(["apps", "Messages", "glow", "dot", "opacity"], to: .number(0.5))
    #expect(
      edited.rendered
        == "[apps.Messages]\nglow = { color = \"green\", dot = { enabled = false, opacity = 0.5 } }\n"
    )
    try edited.remove(["apps", "Messages", "glow", "dot", "enabled"])
    try edited.remove(["apps", "Messages", "glow", "dot", "opacity"])
    #expect(edited.rendered == "[apps.Messages]\nglow = { color = \"green\", dot = {} }\n")
  }

  @Test("writing into `{}` opens it up again")
  func setIntoEmptyBraces() throws {
    var edited = try document("[apps.Slack]\nglow = {}\n")
    try edited.set(["apps", "Slack", "glow", "color"], to: .string("blue"))
    #expect(edited.rendered == "[apps.Slack]\nglow = { color = \"blue\" }\n")
  }

  @Test("subscribing an app to an effect writes `{}`")
  func subscribe() throws {
    var edited = try document("[apps.Slack]\nglow = {}\n")
    try edited.set(["apps", "Slack", "shelf"], to: .emptyTable())
    #expect(edited.rendered == "[apps.Slack]\nglow = {}\nshelf = {}\n")
    #expect(edited.config.app(named: "Slack")?.shelf != nil)
    // Asking again for the table that is already there is nothing to do.
    try edited.set(["apps", "Slack", "glow"], to: .emptyTable())
    #expect(edited.rendered == "[apps.Slack]\nglow = {}\nshelf = {}\n")
  }

  // MARK: - Removing a line

  @Test("removing a key takes its trailing comment and leaves no blank line")
  func removeTakesComment() throws {
    var edited = try document()
    try edited.remove(["glow", "pulse", "crossfade-ms"])
    #expect(!edited.rendered.contains("crossfade-ms"))
    #expect(!edited.rendered.contains("when several apps share one edge"))
    #expect(edited.config.glow.pulse.crossfadeMS == PulseSettings().crossfadeMS)
    // One line fewer, and nothing else moved.
    let before = ConfigExample.text.split(
      omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    let after = edited.rendered.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    #expect(after.count == before.count - 1)
    #expect(after == before.filter { !$0.contains("crossfade-ms") })
  }

  @Test("a key the file doesn't set is left alone")
  func removeAbsent() throws {
    var edited = try document()
    try edited.remove(["glow", "pulse", "min-opacity", "nope"])
    try edited.remove(["shelf", "anchor", "deeper"])
    #expect(edited.rendered == ConfigExample.text)
  }

  @Test("a CRLF file keeps its line endings")
  func crlfPreserved() throws {
    var edited = try document("[glow]\r\ncolor = \"green\"\r\n")
    try edited.set(["glow", "edge"], to: .string("left"))
    #expect(edited.rendered == "[glow]\r\ncolor = \"green\"\r\nedge = \"left\"\r\n")
    try edited.remove(["glow", "color"])
    #expect(edited.rendered == "[glow]\r\nedge = \"left\"\r\n")
  }

  // MARK: - Expansion, the one edit that moves lines

  @Test("expanding an inline table gives it a header of its own")
  func expand() throws {
    var edited = try document(
      """
      [apps.Messages]
      glow = { color = "green" }
      shelf = {}

      """)
    try edited.expand(["apps", "Messages", "glow"])
    #expect(
      edited.rendered == """
        [apps.Messages]
        shelf = {}

        [apps.Messages.glow]
        color = "green"

        """)
    #expect(edited.config.app(named: "Messages")?.glow?.base.color == .named(.green))
  }

  @Test("expansion is what lets a badge-kind override be written at all")
  func expandThenOverride() throws {
    var edited = try document("[apps.Messages]\nshelf = {}\nglow = { color = \"green\" }\n")
    try edited.expand(["apps", "Messages", "glow"])
    try edited.set(["apps", "Messages", "glow", "dot", "enabled"], to: .bool(false))
    #expect(
      edited.rendered == """
        [apps.Messages]
        shelf = {}

        [apps.Messages.glow]
        color = "green"

        [apps.Messages.glow.dot]
        enabled = false

        """)
    #expect(edited.config.app(named: "Messages")?.glow?.dot?.enabled == false)
  }

  @Test("expansion carries the line's comment onto the header")
  func expandKeepsComment() throws {
    var edited = try document("[apps.Slack]\nglow = { color = \"blue\" }  # Slack is blue now\n")
    try edited.expand(["apps", "Slack", "glow"])
    #expect(
      edited.rendered == """
        [apps.Slack]

        [apps.Slack.glow]  # Slack is blue now
        color = "blue"

        """)
  }

  @Test("expanding an empty inline table keeps the subscription")
  func expandEmpty() throws {
    var edited = try document("[apps.Slack]\nglow = {}\n")
    try edited.expand(["apps", "Slack", "glow"])
    #expect(edited.rendered == "[apps.Slack]\n\n[apps.Slack.glow]\n")
    #expect(edited.config.app(named: "Slack")?.glow != nil)
  }

  @Test("expansion refuses where there is nowhere for the block to go")
  func expandRefused() throws {
    // Nested inside another inline table.
    var nested = try document("[apps.Messages]\nglow = { dot = { enabled = false } }\n")
    #expect(throws: ConfigSyntaxError.self) {
      try nested.expand(["apps", "Messages", "glow", "dot"])
    }
    #expect(nested.rendered == "[apps.Messages]\nglow = { dot = { enabled = false } }\n")

    // A table the file only ever made with a dotted key has no run of lines to sit after.
    var dotted = try document("apps.Slack.glow = { color = \"blue\" }\n")
    #expect(throws: ConfigSyntaxError.self) {
      try dotted.expand(["apps", "Slack", "glow"])
    }
  }

  @Test("a key under a table a dotted key made is refused by name")
  func setUnderDottedTable() throws {
    var edited = try document("apps.Slack.glow = { color = \"blue\" }\n")
    let error = #expect(throws: ConfigSyntaxError.self) {
      try edited.set(["apps", "Slack", "bundle-id"], to: .string("com.tinyspeck.slackmacgap"))
    }
    #expect(error?.message.contains("is written as a dotted key") == true)
    #expect(edited.rendered == "apps.Slack.glow = { color = \"blue\" }\n")
  }

  @Test("a table the file doesn't write between braces is left alone")
  func expandAbsent() throws {
    var edited = try document()
    try edited.expand(["glow"])
    try edited.expand(["apps", "Nothing", "glow"])
    #expect(edited.rendered == ConfigExample.text)
  }
}
