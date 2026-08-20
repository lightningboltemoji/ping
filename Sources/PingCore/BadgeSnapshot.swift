//
//  BadgeSnapshot.swift
//  PingCore
//

import Foundation

/// What the Dock looked like at one moment. A plain value, so the resolver can be run
/// headless against a fixture.
public struct BadgeSnapshot: Equatable, Sendable {
  /// Keyed by the app's Dock title, which is also the `[apps.<key>]` table name.
  public var badges: [String: Badge] = [:]
  /// Everything in the Dock, badged or not — the settings picker offers these.
  public var dockTitles: [String] = []
  /// Where each app lives, so `PingUI` can ask `NSWorkspace` for an icon without
  /// `NSImage` appearing in a value type down here.
  public var appURLs: [String: URL] = [:]

  public init(
    badges: [String: Badge] = [:],
    dockTitles: [String] = [],
    appURLs: [String: URL] = [:]
  ) {
    self.badges = badges
    self.dockTitles = dockTitles
    self.appURLs = appURLs
  }
}
