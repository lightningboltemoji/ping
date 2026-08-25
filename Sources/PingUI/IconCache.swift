//
//  IconCache.swift
//  PingUI
//
//  App icons by Dock title, fetched once and kept. Three surfaces want them now — the shelf, the
//  notch and the settings window — and asking `NSWorkspace` is a disk read.
//
//  One cache for the process rather than one per surface: the same icons keyed the same way, and a
//  second copy would only mean reading the same files twice.
//
//  The URL arrives with the reading of the Dock rather than being looked up here, which is what
//  lets a `BadgeSnapshot` stay a value type with no `NSImage` in it.
//

import AppKit

@MainActor
final class IconCache {

  static let shared = IconCache()

  private(set) var images: [String: NSImage] = [:]

  /// Fetch this app's icon unless it is already held. A name with no URL is left alone: the
  /// Dock reading is the only thing that knows where an app lives.
  func load(_ name: String, from url: URL?) {
    guard images[name] == nil, let url else { return }
    images[name] = NSWorkspace.shared.icon(forFile: url.path)
  }

  /// This app's icon, fetched now if it has not been already. What a view asks, since a view has
  /// nowhere to put a separate loading pass.
  func image(_ name: String, from url: URL?) -> NSImage? {
    load(name, from: url)
    return images[name]
  }

  subscript(name: String) -> NSImage? { images[name] }
}
