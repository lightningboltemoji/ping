//
//  DockItem.swift
//  PingCore
//
//  Adapted from https://github.com/pock/pock/blob/9ee414fc35abe933057c87fab082bb9e67f5a34c/Pock/Private/PockDockHelper/PockDockHelper.m
//
//  Created by Tanner on 9/13/25.
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation
import PingConfig

nonisolated(unsafe) let kAXStatusLabelAttribute = "AXStatusLabel" as CFString

/// One application item in the macOS Dock, and the accessibility element behind it.
public struct DockItem {
  public let title: String
  public let axElement: AXUIElement

  public var appURL: URL? {
    var urlRef: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      self.axElement, kAXURLAttribute as CFString, &urlRef)
    guard error == .success else { return nil }
    return urlRef as? URL
  }

  /// The badge as the Dock spells it: `nil` for none, `""` for a bare red dot, digits for
  /// a count. That is exactly the shape `BadgeKind` splits on.
  public func badge() -> Badge? {
    var statusLabel: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      self.axElement,
      kAXStatusLabelAttribute,
      &statusLabel
    )

    guard error == .success else {
      return nil
    }

    let s = statusLabel as? String
    if let s = s, s.allSatisfy(\.isNumber) {
      return Badge(raw: s)
    } else {
      return Badge(raw: "")
    }
  }
}

/// A badge, kept as the Dock's own string so a count can be compared against a previously
/// acknowledged count without losing the difference between `""` and `"0"`.
public struct Badge: Equatable, Sendable {
  public let raw: String

  public init(raw: String) {
    self.raw = raw
  }

  public var kind: BadgeKind { raw.isEmpty ? .dot : .count }
  public var count: Int? { Int(raw) }
}
