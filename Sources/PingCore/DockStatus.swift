//
//  DockStatus.swift
//  PingCore
//
//  What `watch` publishes: every application in the Dock, its badge as the Dock spells it, and
//  what the user last said about it. A fact about the Dock rather than the config, so an app the
//  file never mentions is here too — and a pure function of its inputs, like the resolver.
//

import Foundation

public struct DockStatus: Equatable, Sendable, Encodable {

  /// Bumped when a key changes meaning or goes away; a new key is not a new version.
  public static let version = 1

  public struct App: Equatable, Sendable, Encodable {
    /// The Dock title, which is also the `[apps.<key>]` table name.
    public var name: String
    /// `nil` for no badge, `""` for a bare dot, otherwise exactly what the Dock draws.
    public var badge: String?
    /// The badge as a number, when it is one.
    public var count: Int?
    /// Covered by an acknowledgement, by the rules in `RuntimeState.isCovered`.
    public var acknowledged: Bool
    public var path: String?

    public init(
      name: String, badge: String? = nil, count: Int? = nil, acknowledged: Bool = false,
      path: String? = nil
    ) {
      self.name = name
      self.badge = badge
      self.count = count
      self.acknowledged = acknowledged
      self.path = path
    }

    // Every key, always: a reader that merges each line into the last would otherwise keep a
    // badge that went away.
    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(name, forKey: .name)
      try container.encode(badge, forKey: .badge)
      try container.encode(count, forKey: .count)
      try container.encode(acknowledged, forKey: .acknowledged)
      try container.encode(path, forKey: .path)
    }

    private enum CodingKeys: String, CodingKey {
      case name, badge, count, acknowledged, path
    }
  }

  public var snoozed: Bool
  /// Sorted by name, one per title.
  public var apps: [App]

  public init(snoozed: Bool = false, apps: [App] = []) {
    self.snoozed = snoozed
    self.apps = apps
  }

  /// The live reading only: a settings preview's stand-ins are not the Dock.
  public init(snapshot: BadgeSnapshot, runtime: RuntimeState, now: Date) {
    let names = Set(snapshot.dockTitles).union(snapshot.badges.keys).sorted()
    self.init(
      snoozed: runtime.isSnoozed(at: now),
      apps: names.map { name in
        let badge = snapshot.badges[name]
        return App(
          name: name,
          badge: badge?.raw,
          count: badge?.kind == .count ? badge?.count : nil,
          acknowledged: badge.map { runtime.isCovered(name, badge: $0) } ?? false,
          path: snapshot.appURLs[name].map(Self.path(of:)))
      })
  }

  /// A bundle's URL is a directory's, and its path would end in `/`.
  private static func path(of url: URL) -> String {
    let path = url.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  /// One line of `watch`: compact JSON, keys sorted so the same reading is the same bytes.
  public var line: Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = (try? encoder.encode(self)) ?? Data("{}".utf8)
    data.append(0x0A)
    return data
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.version, forKey: .version)
    try container.encode(snoozed, forKey: .snoozed)
    try container.encode(apps, forKey: .apps)
  }

  private enum CodingKeys: String, CodingKey {
    case version, snoozed, apps
  }
}
