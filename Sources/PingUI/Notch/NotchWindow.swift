//
//  NotchWindow.swift
//  PingUI
//
//  One window per display, built at the strip's widest and never moved or resized: a window that
//  grew would be asking the window server to re-place it over the menu bar sixty times a second.
//  What moves is one layer we own.
//
//  AppKit does not push a borderless window out of the menu bar strip, so there is no
//  `constrainFrameRect` override here to keep it there.
//

import AppKit
import PingConfig
import PingCore

@MainActor
final class NotchWindow: NSWindow {

  let strip: NotchLayer

  /// The widest the strip can ever be: the notch, plus the whole budget on each side.
  static func frame(for geometry: NotchGeometry, settings: NotchSettings) -> NSRect {
    let width = geometry.rect.width + settings.maxWidth * 2
    return NSRect(
      x: geometry.rect.midX - width / 2, y: geometry.rect.minY,
      width: width, height: geometry.rect.height)
  }

  init(geometry: NotchGeometry, settings: NotchSettings) {
    let frame = Self.frame(for: geometry, settings: settings)
    strip = NotchLayer(geometry: geometry, settings: settings, size: frame.size)

    super.init(
      contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    // The floor: at `.mainMenu` and below, the menu bar's own text composites above the window.
    level = .statusBar
    ignoresMouseEvents = true
    // The strip hangs in the one piece of furniture a full-screen space keeps, so it takes
    // `.fullScreenAuxiliary` as well as the two an effect always needs.
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

    let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
    host.wantsLayer = true
    host.layer?.addSublayer(strip.shape)
    contentView = host

    // Without the screen's own scale the rounded corners rasterise at 1× and read as steps.
    strip.contentsScale = backingScaleFactor
  }
}
