import Testing

@testable import PingCore

/// `shouldSuppress`'s count logic came across from `DockPoller` unchanged. It was subtle
/// and untested; this is the test it never had.
@Suite("Acknowledgement")
struct AcknowledgementTests {

  @Test(
    "a count stays covered until it grows past what was acknowledged",
    arguments: [
      (current: "3", ack: "3", covered: true),
      (current: "2", ack: "3", covered: true),
      (current: "4", ack: "3", covered: false),
      (current: "0", ack: "3", covered: true),
    ])
  func counts(current: String, ack: String, covered: Bool) {
    #expect(RuntimeState.isCovered(current: current, byAcknowledged: ack) == covered)
  }

  @Test("a count arriving after a bare dot is new; another dot is not")
  func dotsAndCounts() {
    #expect(RuntimeState.isCovered(current: "", byAcknowledged: "") == true)
    #expect(RuntimeState.isCovered(current: "1", byAcknowledged: "") == false)
    // A dot after a count is a different kind of badge, not a smaller one.
    #expect(RuntimeState.isCovered(current: "", byAcknowledged: "3") == false)
  }

  @Test("acknowledging takes everything currently badged")
  func acknowledgeAll() {
    var runtime = RuntimeState()
    runtime.acknowledge(
      BadgeSnapshot(badges: ["Slack": Badge(raw: "3"), "Mail": Badge(raw: "")]))
    #expect(runtime.acknowledged == ["Slack": "3", "Mail": ""])
    #expect(runtime.hasAcknowledgedApps)
  }

  @Test("a badge that goes away forgets its acknowledgement")
  func badgeDisappears() {
    var runtime = RuntimeState()
    runtime.acknowledged = ["Slack": "3"]
    runtime.reconcile(with: BadgeSnapshot())
    #expect(runtime.acknowledged.isEmpty)
  }

  @Test("a badge that falls is followed down, so returning to the old level is new again")
  func badgeFalls() {
    var runtime = RuntimeState()
    runtime.acknowledged = ["Slack": "3"]

    runtime.reconcile(with: BadgeSnapshot(badges: ["Slack": Badge(raw: "1")]))
    #expect(runtime.acknowledged["Slack"] == "1")

    // Back up to 3 — which was acknowledged once, but is an increase from 1.
    runtime.reconcile(with: BadgeSnapshot(badges: ["Slack": Badge(raw: "3")]))
    #expect(runtime.acknowledged["Slack"] == nil)
  }

  @Test("a badge that grows past the acknowledgement drops it")
  func badgeGrows() {
    var runtime = RuntimeState()
    runtime.acknowledged = ["Slack": "3"]
    runtime.reconcile(with: BadgeSnapshot(badges: ["Slack": Badge(raw: "4")]))
    #expect(runtime.acknowledged.isEmpty)
  }
}
