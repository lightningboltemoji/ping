//
//  IconCache.swift
//  PingUI
//
//  App icons by Dock title, fetched once and kept. Two renderers want them now, and asking
//  `NSWorkspace` is a disk read.
//
//  The URL arrives with the reading of the Dock rather than being looked up here, which is what
//  lets a `BadgeSnapshot` stay a value type with no `NSImage` in it.
//

import AppKit

@MainActor
final class IconCache {

  private(set) var images: [String: NSImage] = [:]

  /// Fetch this app's icon unless it is already held. A name with no URL is left alone: the
  /// Dock reading is the only thing that knows where an app lives.
  func load(_ name: String, from url: URL?) {
    guard images[name] == nil, let url else { return }
    images[name] = NSWorkspace.shared.icon(forFile: url.path)
  }

  subscript(name: String) -> NSImage? { images[name] }
}
