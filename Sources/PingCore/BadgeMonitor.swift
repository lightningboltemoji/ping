//
//  BadgeMonitor.swift
//  PingCore
//
//  The polling loop, as an `AsyncStream<BadgeSnapshot>`. The interval is read through a
//  closure rather than captured, so `poll-interval-ms` can change under a running loop
//  without tearing the stream down.
//

import Foundation
import os

private let logger = Logger(subsystem: "Ping", category: "polling")

@MainActor
public final class BadgeMonitor {

  /// `BADGES` is how the renderers get exercised without waiting for a real notification: a JSON
  /// array of `{"appName": "Slack", "badge": "3", "at": 5}`, where
  /// `at` is seconds after launch and a null badge clears one.
  private struct BadgeOverride: Decodable {
    let appName: String
    let badge: String?
    let at: Double?
  }

  private let overrides: [BadgeOverride]?
  private let launchTime: Date
  private var task: Task<Void, Never>?

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    launchTime: Date = Date()
  ) {
    self.launchTime = launchTime
    if let json = environment["BADGES"],
      let data = json.data(using: .utf8),
      let entries = try? JSONDecoder().decode([BadgeOverride].self, from: data)
    {
      self.overrides = entries
      logger.info("Using BADGES override with \(entries.count) entries")
    } else {
      self.overrides = nil
    }
  }

  deinit {
    task?.cancel()
  }

  /// Yields whenever the Dock's badges change. Cancel the returned stream's task, or call
  /// `stop()`, to end the loop.
  public func snapshots(
    interval: @escaping @MainActor () -> Duration
  ) -> AsyncStream<BadgeSnapshot> {
    stop()
    return AsyncStream { continuation in
      let task = Task { @MainActor in
        var last: BadgeSnapshot?
        while !Task.isCancelled {
          let snapshot = read(at: Date())
          if snapshot != last {
            last = snapshot
            continuation.yield(snapshot)
          }
          try? await Task.sleep(for: interval())
        }
        continuation.finish()
      }
      self.task = task
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func stop() {
    task?.cancel()
    task = nil
  }

  /// One read of the Dock, with any `BADGES` overrides that have come due applied on top.
  public func read(at now: Date) -> BadgeSnapshot {
    var snapshot = DockReader.read()
    guard let overrides else { return snapshot }

    let elapsed = now.timeIntervalSince(launchTime)
    for entry in overrides where elapsed >= (entry.at ?? 0) {
      if let badge = entry.badge {
        snapshot.badges[entry.appName] = Badge(raw: badge)
      } else {
        snapshot.badges.removeValue(forKey: entry.appName)
      }
      if !snapshot.dockTitles.contains(entry.appName) {
        snapshot.dockTitles.append(entry.appName)
        snapshot.dockTitles.sort()
      }
    }
    return snapshot
  }
}
