//
//  ShelfWindow.swift
//  PingUI
//
//  Was `FloatingDockWindow`. The view is handed values rather than reading an observable
//  app state, so the window swaps its root view when the render state changes.
//

import PingConfig
import PingCore
import SwiftUI

@MainActor
final class ShelfWindow: NSWindow {

  private let hosting: NSHostingView<AnyView>

  static func windowFrame(
    anchor: ShelfAnchor, margin: Double, screen: NSRect
  ) -> NSRect {
    let windowHeight: CGFloat = 80
    let x = screen.origin.x + margin
    let width = screen.width - margin * 2
    let y = anchor.isTop ? screen.maxY - margin - windowHeight : screen.origin.y + margin
    return NSRect(x: x, y: y, width: width, height: windowHeight)
  }

  init(shelf: ShelfState, icons: [String: NSImage], screen: NSRect) {
    let frame = Self.windowFrame(
      anchor: shelf.settings.anchor, margin: shelf.settings.margin, screen: screen)
    hosting = NSHostingView(rootView: Self.rootView(shelf: shelf, icons: icons))

    super.init(
      contentRect: frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: true
    )

    self.level = .statusBar
    self.isOpaque = false
    self.backgroundColor = .clear
    self.ignoresMouseEvents = true
    self.hasShadow = false
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]
    self.contentView = hosting
  }

  func update(shelf: ShelfState, icons: [String: NSImage]) {
    hosting.rootView = Self.rootView(shelf: shelf, icons: icons)
  }

  private static func rootView(shelf: ShelfState, icons: [String: NSImage]) -> AnyView {
    let alignment: Alignment
    switch shelf.settings.anchor {
    case .topLeft, .bottomLeft: alignment = .leading
    case .topCenter, .bottomCenter: alignment = .center
    case .topRight, .bottomRight: alignment = .trailing
    }
    return AnyView(
      ShelfView(settings: shelf.settings, items: shelf.items, icons: icons)
        .frame(maxWidth: .infinity, alignment: alignment))
  }
}
