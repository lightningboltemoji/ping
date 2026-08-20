import Testing

@testable import PingConfig

@Suite("Example config")
struct ConfigExampleTests {

  @Test("the shipped example is valid, and says what it looks like it says")
  func exampleParses() throws {
    let parsed = try Config.parse(ConfigExample.text)
    #expect(parsed.diagnostics.isEmpty)

    let config = parsed.config
    #expect(config.general.pollIntervalMS == 500)
    #expect(config.general.monitors == .main)
    #expect(config.general.suppressWhenFocused)
    #expect(!config.general.launchAtLogin)

    #expect(config.glow.pulse == PulseSettings())  // the example writes the built-ins
    #expect(config.shelf == ShelfSettings())

    #expect(config.apps.map(\.name) == ["Slack", "Google Chrome", "Mail", "Messages"])

    // Slack — glow purple from the left, and on the shelf.
    let slack = try #require(config.app(named: "Slack"))
    #expect(config.resolvedGlow(for: slack, badge: .count)?.color == PingColor("#611f69"))
    #expect(config.resolvedGlow(for: slack, badge: .count)?.edge == .left)
    #expect(config.shelfShows(slack))

    let chrome = try #require(config.app(named: "Google Chrome"))
    #expect(config.resolvedGlow(for: chrome, badge: .dot) == ResolvedGlow.builtin)
    #expect(!config.shelfShows(chrome))

    let mail = try #require(config.app(named: "Mail"))
    let mailGlow = try #require(config.resolvedGlow(for: mail, badge: .count))
    #expect(mailGlow.color == .named(.blue))
    #expect(mailGlow.edge == .right)
    #expect(mailGlow.size == 0.6)
    #expect(mailGlow.opacity == 0.7)

    // Messages — green, but only when there is an actual count.
    let messages = try #require(config.app(named: "Messages"))
    #expect(config.resolvedGlow(for: messages, badge: .count)?.color == .named(.green))
    #expect(config.resolvedGlow(for: messages, badge: .dot) == nil)
    #expect(config.shelfShows(messages))
  }
}
