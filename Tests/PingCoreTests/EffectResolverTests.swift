import Foundation
import PingConfig
import Testing

@testable import PingCore

@Suite("Effect resolver")
struct EffectResolverTests {

  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func config(_ text: String) throws -> Config {
    try Config.parse(text).config
  }

  private func render(
    _ config: Config,
    _ snapshot: BadgeSnapshot,
    _ runtime: RuntimeState = RuntimeState()
  ) -> RenderState {
    EffectResolver.renderState(config: config, snapshot: snapshot, runtime: runtime, now: now)
  }

  private let twoApps = """
    [apps.Slack]
    glow  = { color = "#611f69", edge = "left" }
    shelf = {}

    [apps.Mail]
    glow = { color = "blue" }
    """

  @Test("only badged apps render")
  func onlyBadgedApps() throws {
    let state = render(try config(twoApps), BadgeSnapshot(badges: ["Slack": Badge(raw: "3")]))
    #expect(state.glows.map(\.appName) == ["Slack"])
    #expect(state.shelf?.items.map(\.appName) == ["Slack"])
  }

  @Test("an app in the Dock that the file does not mention renders nothing")
  func unconfiguredApp() throws {
    let state = render(try config(twoApps), BadgeSnapshot(badges: ["Notes": Badge(raw: "1")]))
    #expect(state.isEmpty)
  }

  @Test("the shelf is absent, not empty, when nothing belongs on it")
  func emptyShelfIsNil() throws {
    let state = render(try config(twoApps), BadgeSnapshot(badges: ["Mail": Badge(raw: "1")]))
    #expect(state.glows.count == 1)
    #expect(state.shelf == nil)
  }

  @Test("snooze holds everything back")
  func snooze() throws {
    var runtime = RuntimeState()
    runtime.snoozedUntil = now.addingTimeInterval(60)
    let snapshot = BadgeSnapshot(badges: ["Slack": Badge(raw: "3")])
    #expect(render(try config(twoApps), snapshot, runtime).isEmpty)

    runtime.snoozedUntil = now.addingTimeInterval(-1)
    #expect(!render(try config(twoApps), snapshot, runtime).isEmpty)
  }

  @Test("an acknowledged badge is held back until it grows")
  func acknowledged() throws {
    var runtime = RuntimeState()
    runtime.acknowledged = ["Slack": "3"]
    #expect(
      render(try config(twoApps), BadgeSnapshot(badges: ["Slack": Badge(raw: "3")]), runtime)
        .isEmpty)
    #expect(
      !render(try config(twoApps), BadgeSnapshot(badges: ["Slack": Badge(raw: "4")]), runtime)
        .isEmpty)
  }

  @Test("suppress-when-focused only applies when it is asked for")
  func suppressWhenFocused() throws {
    var runtime = RuntimeState()
    runtime.frontmostAppName = "Slack"
    let snapshot = BadgeSnapshot(badges: ["Slack": Badge(raw: "3")])

    #expect(!render(try config(twoApps), snapshot, runtime).isEmpty)

    let suppressing = try config("suppress-when-focused = true\n\n" + twoApps)
    #expect(render(suppressing, snapshot, runtime).isEmpty)
  }

  @Test("an app that declares bundle-id is matched on it rather than on its Dock title")
  func frontmostByBundleID() throws {
    let parsed = try config(
      """
      suppress-when-focused = true

      [apps.Slack]
      bundle-id = "com.tinyspeck.slackmacgap"
      glow = {}
      """)
    let snapshot = BadgeSnapshot(badges: ["Slack": Badge(raw: "3")])

    // The frontmost app's localized name disagrees with the Dock title, which is exactly
    // the case bundle-id exists to fix.
    var runtime = RuntimeState()
    runtime.frontmostAppName = "Slack (beta)"
    runtime.frontmostBundleID = "com.tinyspeck.slackmacgap"
    #expect(render(parsed, snapshot, runtime).isEmpty)

    runtime.frontmostBundleID = "com.apple.mail"
    #expect(!render(parsed, snapshot, runtime).isEmpty)
  }

  @Test("a preview stands in for the live snapshot, and ignores every suppression")
  func preview() throws {
    var runtime = RuntimeState()
    runtime.snoozedUntil = now.addingTimeInterval(60)
    runtime.acknowledged = ["Slack": "3"]
    runtime.preview = EffectPreview(snapshot: BadgeSnapshot(badges: ["Slack": Badge(raw: "3")]))

    let state = render(try config(twoApps), BadgeSnapshot(), runtime)
    #expect(state.glows.map(\.appName) == ["Slack"])
    #expect(state.shelf?.items.map(\.appName) == ["Slack"])
  }

  @Test("a preview draws only the effect it is about")
  func previewIsScopedToOneEffect() throws {
    let parsed = try config(twoApps)
    let badged = BadgeSnapshot(badges: ["Slack": Badge(raw: "3")])

    var runtime = RuntimeState()
    runtime.preview = EffectPreview(snapshot: badged, effects: .shelf)
    let shelfOnly = render(parsed, BadgeSnapshot(), runtime)
    #expect(shelfOnly.glows.isEmpty)
    #expect(shelfOnly.shelf?.items.map(\.appName) == ["Slack"])

    runtime.preview = EffectPreview(snapshot: badged, effects: .glow)
    let glowOnly = render(parsed, BadgeSnapshot(), runtime)
    #expect(glowOnly.glows.map(\.appName) == ["Slack"])
    #expect(glowOnly.shelf == nil)
  }

  @Test("a preview's stand-in apps are drawn, and never override the file's own")
  func previewSamples() throws {
    var runtime = RuntimeState()
    runtime.preview = EffectPreview(
      snapshot: BadgeSnapshot(badges: ["Notes": Badge(raw: "1"), "Mail": Badge(raw: "1")]),
      effects: .shelf,
      // Notes is nobody's app, so it stands in; Mail *is* in the file, and the file's Mail has
      // no shelf, so the stand-in must not put it on one.
      samples: [
        AppConfig(name: "Notes", shelf: AppShelf()),
        AppConfig(name: "Mail", shelf: AppShelf()),
      ])

    let state = render(try config(twoApps), BadgeSnapshot(), runtime)
    #expect(state.shelf?.items.map(\.appName) == ["Notes"])
  }

  @Test("the render state carries the pulse and the monitor mode along")
  func carriesGlobals() throws {
    let parsed = try config(
      """
      monitors = "all"

      [glow.pulse]
      duration-ms = 1200
      """)
    let state = render(parsed, BadgeSnapshot())
    #expect(state.monitors == .all)
    #expect(state.pulse.durationMS == 1200)
  }

  @Test("a badge kind picks its own settings")
  func badgeKinds() throws {
    let parsed = try config(
      """
      [apps.Messages.glow]
      color = "green"

      [apps.Messages.glow.dot]
      enabled = false
      """)
    #expect(render(parsed, BadgeSnapshot(badges: ["Messages": Badge(raw: "")])).isEmpty)
    #expect(!render(parsed, BadgeSnapshot(badges: ["Messages": Badge(raw: "2")])).isEmpty)
  }

  @Test("shelf items carry the app's location so the UI can find an icon")
  func shelfItemsCarryURLs() throws {
    let url = URL(fileURLWithPath: "/Applications/Slack.app")
    let snapshot = BadgeSnapshot(
      badges: ["Slack": Badge(raw: "3")], appURLs: ["Slack": url])
    let state = render(try config(twoApps), snapshot)
    #expect(state.shelf?.items.first?.appURL == url)
    #expect(state.shelf?.items.first?.badge.kind == .count)
  }
}
