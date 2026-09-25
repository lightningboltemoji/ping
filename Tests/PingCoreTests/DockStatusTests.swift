import Foundation
import Testing

@testable import PingCore

@Suite("Dock status")
struct DockStatusTests {

  private let now = Date(timeIntervalSince1970: 1_790_000_000)

  private func status(
    _ snapshot: BadgeSnapshot, runtime: RuntimeState = RuntimeState()
  ) -> DockStatus {
    DockStatus(snapshot: snapshot, runtime: runtime, now: now)
  }

  @Test("every app in the Dock, badged or not, once each and sorted, with where it lives")
  func everyApp() {
    let snapshot = BadgeSnapshot(
      badges: ["Slack": Badge(raw: "3")],
      dockTitles: ["Slack", "Finder", "Ghostty", "Ghostty"],
      appURLs: ["Slack": URL(filePath: "/Applications/Slack.app/", directoryHint: .isDirectory)])
    let apps = status(snapshot).apps
    #expect(apps.map(\.name) == ["Finder", "Ghostty", "Slack"])
    #expect(apps[2] == .init(name: "Slack", badge: "3", count: 3, path: "/Applications/Slack.app"))
    #expect(apps[0] == .init(name: "Finder"))
  }

  @Test("a word is published as the Dock spells it, with no count, and drawn as a dot")
  func words() {
    let snapshot = BadgeSnapshot(
      badges: ["Mail": Badge(raw: "!"), "Notes": Badge(raw: "")],
      dockTitles: ["Mail", "Notes"])
    let apps = status(snapshot).apps
    #expect(apps[0] == .init(name: "Mail", badge: "!"))
    #expect(apps[1] == .init(name: "Notes", badge: ""))
    #expect(Badge(raw: "!").kind == .dot)
    #expect(Badge(raw: "New").kind == .dot)
    #expect(Badge(raw: "12").kind == .count)
  }

  @Test("acknowledged is the resolver's own answer, so a count that grew past it is not")
  func acknowledged() {
    var runtime = RuntimeState()
    runtime.acknowledged = ["Slack": "3", "Mail": "2"]
    let snapshot = BadgeSnapshot(
      badges: ["Slack": Badge(raw: "2"), "Mail": Badge(raw: "5")],
      dockTitles: ["Slack", "Mail", "Finder"])
    let apps = status(snapshot, runtime: runtime).apps
    #expect(apps.map(\.acknowledged) == [false, false, true])  // Finder, Mail, Slack
  }

  @Test("snoozed follows the clock rather than the field being set")
  func snoozed() {
    var runtime = RuntimeState()
    runtime.snoozedUntil = now.addingTimeInterval(60)
    #expect(status(BadgeSnapshot(), runtime: runtime).snoozed)
    runtime.snoozedUntil = now.addingTimeInterval(-1)
    #expect(!status(BadgeSnapshot(), runtime: runtime).snoozed)
  }

  @Test("a line is one compact JSON object with every key present, nulls included")
  func line() {
    let snapshot = BadgeSnapshot(
      badges: ["Slack": Badge(raw: "3")],
      dockTitles: ["Finder", "Slack"],
      appURLs: ["Slack": URL(filePath: "/Applications/Slack.app")])
    let text = String(decoding: status(snapshot).line, as: UTF8.self)
    #expect(
      text == #"{"apps":[{"acknowledged":false,"badge":null,"count":null,"name":"Finder","#
        + #""path":null},{"acknowledged":false,"badge":"3","count":3,"name":"Slack","#
        + #""path":"/Applications/Slack.app"}],"snoozed":false,"version":1}"# + "\n")
  }

  @Test("the engine publishes the live reading, not a preview's stand-ins")
  @MainActor
  func engineIgnoresPreview() {
    let engine = EffectEngine()
    engine.apply(BadgeSnapshot(badges: ["Slack": Badge(raw: "1")], dockTitles: ["Slack"]))
    engine.runtime.preview = EffectPreview(
      snapshot: BadgeSnapshot(badges: ["Mail": Badge(raw: "9")], dockTitles: ["Mail"]),
      effects: [.glow])
    #expect(engine.dockStatus.apps.map(\.name) == ["Slack"])
  }
}
