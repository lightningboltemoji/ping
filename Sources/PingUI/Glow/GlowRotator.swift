//
//  GlowRotator.swift
//  PingUI
//
//  Created by Tanner on 3/4/26.
//
//  Carried over from `GlowConfigRotator`, now cycling `ResolvedGlow` values.
//  Their equality is exact — the old fuzzy component compare existed only because the
//  configs carried an `NSColor`.
//

import PingConfig

struct GlowRotator {
  /// LRU order: front = next to show
  private var queue: [ResolvedGlow] = []
  private(set) var current: ResolvedGlow?

  var isEmpty: Bool { current == nil && queue.isEmpty }

  var hasMultiple: Bool {
    current != nil && !queue.isEmpty
  }

  /// Update available glows. New ones go to front of queue, existing ones keep LRU order.
  /// Idempotent with the same set.
  mutating func setAvailable(_ glows: [ResolvedGlow]) {
    guard !glows.isEmpty else {
      queue = []
      current = nil
      return
    }

    // If we have nothing on screen, start fresh
    guard let current else {
      self.current = glows.first
      queue = Array(glows.dropFirst())
      return
    }

    let allKnown = [current] + queue

    // Brand-new glows go to front (highest priority)
    var newQueue: [ResolvedGlow] = []
    for glow in glows where !allKnown.contains(glow) {
      newQueue.append(glow)
    }

    // Existing queue entries still available keep their LRU order
    for glow in queue where glows.contains(glow) {
      newQueue.append(glow)
    }

    queue = newQueue

    // If what is on screen was removed, pull the next one up
    if !glows.contains(current) {
      self.current = queue.isEmpty ? nil : queue.removeFirst()
    }
  }

  /// Advance to the next glow. With one glow this returns it again; with none, `nil`.
  mutating func next() -> ResolvedGlow? {
    guard let current else { return nil }
    guard !queue.isEmpty else { return current }

    let next = queue.removeFirst()
    queue.append(current)
    self.current = next
    return next
  }
}
