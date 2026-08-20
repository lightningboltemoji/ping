import PingConfig
import Testing

@testable import PingUI

/// The edit session, and the two things it exists to make facts rather than flags: whether
/// anything would be written, and why the last edit didn't land.
@Suite("Draft")
struct DraftTests {

  private let file = """
    poll-interval-ms = 250

    [glow]
    color = "green"

    [apps.Slack]
    glow  = { color = "#611f69" }
    shelf = {}

    """

  private func setting(_ key: TOMLKey) throws -> Setting {
    try #require(Setting.setting(for: key))
  }

  @Test("a fresh draft is clean, and renders the file it was opened on")
  func opensClean() throws {
    let draft = try Draft(file)
    #expect(!draft.isDirty)
    #expect(draft.rendered == file)
    #expect(draft.refusal == nil)
    #expect(draft.config.glow.defaults.color == .named(.green))
  }

  @Test("a file that does not parse keeps the window shut")
  func refusesBrokenFile() {
    #expect(throws: ConfigSyntaxError.self) { try Draft("[glow]\ncolour = \"green\"\n") }
  }

  @Test("an edit makes the draft dirty, and setting it back makes it clean again")
  func dirtyIsAFact() throws {
    var draft = try Draft(file)
    try draft.set(setting(["poll-interval-ms"]), to: .number(1000))
    #expect(draft.isDirty)
    #expect(draft.config.general.pollIntervalMS == 1000)

    try draft.set(setting(["poll-interval-ms"]), to: .number(250))
    #expect(!draft.isDirty)
    #expect(draft.rendered == file)
  }

  /// Not a round trip, and deliberately so: the file wrote `color = "green"`, which is what Ping
  /// does anyway, so choosing green takes the line out rather than putting it back.
  @Test("choosing the default for a key the file writes removes that line")
  func writtenDefaultIsUnset() throws {
    var draft = try Draft(file)
    try draft.set(setting(["glow", "color"]), to: .string("blue"))
    try draft.set(setting(["glow", "color"]), to: .string("green"))
    #expect(draft.isDirty)
    #expect(!draft.rendered.contains("color = \"green\""))
    #expect(draft.config.glow.defaults.color == nil)
    #expect(
      draft.config.resolvedGlow(forAppNamed: "Slack", badge: .count)?.color
        == .hex(PingColor("#611f69")!.rgba))
  }

  @Test("choosing a setting's default takes the line out rather than writing it")
  func defaultUnsets() throws {
    var draft = try Draft(file)
    // `bottom` is the built-in the cascade starts from, so the file should say nothing.
    try draft.set(setting(["glow", "edge"]), to: .string("bottom"))
    #expect(!draft.isDirty)
    try draft.set(setting(["glow", "edge"]), to: .string("left"))
    #expect(draft.rendered.contains("edge = \"left\""))
  }

  @Test("a refused edit changes nothing and leaves the complaint on screen")
  func refusalKeepsTheFile() throws {
    var draft = try Draft(file)
    try draft.set(setting(["glow", "size"]), to: .number(9))
    #expect(draft.refusal == "'glow.size' must be between 0.25 and 1.0, got 9.0")
    #expect(!draft.isDirty)
    #expect(draft.rendered == file)

    // And the next edit that lands clears it.
    try draft.set(setting(["glow", "size"]), to: .number(0.5))
    #expect(draft.refusal == nil)
  }

  @Test("an app's keys are edited by key, since the table does not describe them")
  func appEdits() throws {
    var draft = try Draft(file)
    draft.apply(.key(["apps", "Slack", "glow", "edge"], .string("left")))
    #expect(draft.rendered.contains(##"glow  = { color = "#611f69", edge = "left" }"##))
    #expect(draft.config.app(named: "Slack")?.glow?.base.edge == .left)

    draft.apply(.unset(["apps", "Slack", "shelf"]))
    #expect(draft.refusal == nil)
    #expect(draft.config.app(named: "Slack")?.shelf == nil)
    #expect(!draft.rendered.contains("shelf"))
  }

  /// An app's effect is not a value with a default — it is its presence in the file — so taking it
  /// away means taking a whole table out, however the file happened to spell it.
  @Test("an effect written as a header block comes out whole")
  func unsubscribeHeaderForm() throws {
    var draft = try Draft(
      """
      [apps.Messages]
      shelf = {}

      [apps.Messages.glow]
      color = "green"

      [apps.Messages.glow.dot]
      enabled = false

      [shelf]
      opacity = 0.5

      """)
    draft.apply(.unset(["apps", "Messages", "glow"]))
    #expect(draft.refusal == nil)
    #expect(draft.config.app(named: "Messages")?.glow == nil)
    #expect(draft.config.app(named: "Messages")?.shelf != nil)
    #expect(
      draft.rendered == """
        [apps.Messages]
        shelf = {}

        [shelf]
        opacity = 0.5

        """)
  }

  @Test("deleting an app takes every block it owns")
  func deleteApp() throws {
    var draft = try Draft(
      """
      [apps.Messages]
      shelf = {}

      [apps.Messages.glow]
      color = "green"

      [apps.Slack]
      glow = {}

      """)
    draft.apply(.unset(["apps", "Messages"]))
    #expect(draft.refusal == nil)
    #expect(draft.config.apps.map(\.name) == ["Slack"])
    #expect(draft.rendered == "[apps.Slack]\nglow = {}\n")
  }

  @Test("a badge-kind override expands the braces first")
  func expandThenOverride() throws {
    var draft = try Draft(file)
    draft.apply(.expand(["apps", "Slack", "glow"]))
    draft.apply(.key(["apps", "Slack", "glow", "dot", "enabled"], .bool(false)))
    #expect(draft.refusal == nil)
    #expect(draft.config.app(named: "Slack")?.glow?.dot?.enabled == false)
    #expect(draft.rendered.contains("[apps.Slack.glow.dot]"))
  }

  @Test("discard goes back to the file as it was opened")
  func discard() throws {
    var draft = try Draft(file)
    try draft.set(setting(["glow", "color"]), to: .string("blue"))
    try draft.set(setting(["shelf", "icon-size"]), to: .number(48))
    draft.discard()
    #expect(!draft.isDirty)
    #expect(draft.rendered == file)
  }

  @Test("saving makes the draft clean without re-reading the file it wrote")
  func saved() throws {
    var draft = try Draft(file)
    try draft.set(setting(["glow", "color"]), to: .string("blue"))
    let written = draft.rendered
    draft.saved()
    #expect(!draft.isDirty)
    #expect(draft.rendered == written)
    // And Discard now goes back to what was saved, not to what was opened.
    try draft.set(setting(["glow", "color"]), to: .string("red"))
    draft.discard()
    #expect(draft.rendered == written)
  }

  @Test("reloading takes the file's new text as both halves")
  func reload() throws {
    var draft = try Draft(file)
    let changed = file.replacingOccurrences(of: "\"green\"", with: "\"purple\"")
    try draft.reload(changed)
    #expect(!draft.isDirty)
    #expect(draft.config.glow.defaults.color == .named(.purple))

    // A file that stopped parsing leaves the draft exactly as it was.
    #expect(throws: ConfigSyntaxError.self) { try draft.reload("[glow]\ncolour = 1\n") }
    #expect(draft.rendered == changed)
  }
}
