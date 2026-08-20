//
//  RuntimeState.swift
//  PingCore
//
//  Everything that varies while Ping runs and is never written to the file.
//  A value type, so `EffectResolver` stays a pure function of (Config, snapshot, runtime).
//

import Foundation
import PingConfig

public struct RuntimeState: Equatable, Sendable {
  /// When set, effects are held until this moment passes.
  public var snoozedUntil: Date?
  /// Dock title → the badge that was showing when the user acknowledged it. Effects stay
  /// suppressed until the badge grows past it.
  public var acknowledged: [String: String] = [:]
  public var frontmostAppName: String?
  public var frontmostBundleID: String?
  /// What an open settings window is asking to see: a synthetic reading of the Dock the resolver
  /// uses instead of the live one, scoped to the effect being edited. Replaces the three parallel
  /// preview fields the old `AppState` carried.
  public var preview: EffectPreview?

  public init() {}

  public func isSnoozed(at now: Date) -> Bool {
    guard let snoozedUntil else { return false }
    return now < snoozedUntil
  }

  public var hasAcknowledgedApps: Bool { !acknowledged.isEmpty }

  /// Acknowledge everything currently badged.
  public mutating func acknowledge(_ snapshot: BadgeSnapshot) {
    acknowledged = snapshot.badges.mapValues(\.raw)
  }

  /// Whether a badge is still covered by an earlier acknowledgement.
  ///
  /// A count is covered while it stays at or below the acknowledged count; a bare dot is
  /// covered by a bare dot, but a count arriving after a dot is new. Kept verbatim from
  /// the pre-rewrite `DockPoller` — it is subtle, and now it is tested.
  public static func isCovered(current: String, byAcknowledged acknowledged: String) -> Bool {
    if let ackNumber = Int(acknowledged) {
      if let currentNumber = Int(current) {
        return currentNumber <= ackNumber
      }
      return false
    }
    // The acknowledged badge was a bare dot.
    if Int(current) != nil {
      return false
    }
    return true
  }

  public func isCovered(_ appName: String, badge: Badge) -> Bool {
    guard let ack = acknowledged[appName] else { return false }
    return Self.isCovered(current: badge.raw, byAcknowledged: ack)
  }

  /// Fold a new snapshot into the acknowledgements: forget apps whose badge went away,
  /// follow a badge downwards so that returning to the old level counts as new, and drop
  /// the acknowledgement once the badge grows past it.
  public mutating func reconcile(with snapshot: BadgeSnapshot) {
    for (appName, ack) in acknowledged {
      guard let badge = snapshot.badges[appName] else {
        acknowledged.removeValue(forKey: appName)
        continue
      }
      if Self.isCovered(current: badge.raw, byAcknowledged: ack) {
        if badge.raw != ack {
          acknowledged[appName] = badge.raw
        }
      } else {
        acknowledged.removeValue(forKey: appName)
      }
    }
  }
}
