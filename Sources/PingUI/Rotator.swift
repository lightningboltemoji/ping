//
//  Rotator.swift
//  PingUI
//
//  Created by Tanner on 3/4/26.
//
//  An edge holds one glow at a time and a full notch holds one tail at a time, so contention is
//  resolved in time rather than in space (`PRINCIPLES.md` §3). This is the LRU that does it, for
//  both: the newest thing goes first, and what has been seen goes to the back.
//

struct Rotator<Element: Equatable> {
  /// LRU order: front = next to show
  private var queue: [Element] = []
  private(set) var current: Element?

  var isEmpty: Bool { current == nil && queue.isEmpty }

  var hasMultiple: Bool {
    current != nil && !queue.isEmpty
  }

  /// Update what is available. New entries go to the front of the queue, existing ones keep
  /// their LRU order. Idempotent with the same set.
  mutating func setAvailable(_ elements: [Element]) {
    guard !elements.isEmpty else {
      queue = []
      current = nil
      return
    }

    // If we have nothing on screen, start fresh
    guard let current else {
      self.current = elements.first
      queue = Array(elements.dropFirst())
      return
    }

    let allKnown = [current] + queue

    // Brand-new entries go to front (highest priority)
    var newQueue: [Element] = []
    for element in elements where !allKnown.contains(element) {
      newQueue.append(element)
    }

    // Existing queue entries still available keep their LRU order
    for element in queue where elements.contains(element) {
      newQueue.append(element)
    }

    queue = newQueue

    // If what is on screen was removed, pull the next one up
    if !elements.contains(current) {
      self.current = queue.isEmpty ? nil : queue.removeFirst()
    }
  }

  /// Advance to the next one. With one entry this returns it again; with none, `nil`.
  mutating func next() -> Element? {
    guard let current else { return nil }
    guard !queue.isEmpty else { return current }

    let next = queue.removeFirst()
    queue.append(current)
    self.current = next
    return next
  }
}
