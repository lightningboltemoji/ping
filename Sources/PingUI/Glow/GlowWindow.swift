//
//  GlowWindow.swift
//  PingUI
//
//  Created by Tanner on 9/17/25.
//

import Cocoa
import PingConfig
import QuartzCore

class GlowWindow: NSWindow {

  private var glowView: GlowView!
  let edge: Edge

  init(
    screen: NSScreen,
    edge: Edge,
    depth: Double = 0.25,
  ) {
    self.edge = edge
    let sf = screen.frame
    let depthPx = sf.height * CGFloat(depth)

    let windowRect: NSRect
    switch edge {
    case .bottom:
      windowRect = NSRect(
        x: sf.minX, y: sf.minY,
        width: sf.width, height: depthPx)
    case .top:
      windowRect = NSRect(
        x: sf.minX, y: sf.maxY - depthPx,
        width: sf.width, height: depthPx)
    case .left:
      windowRect = NSRect(
        x: sf.minX, y: sf.minY,
        width: depthPx, height: sf.height)
    case .right:
      windowRect = NSRect(
        x: sf.maxX - depthPx, y: sf.minY,
        width: depthPx, height: sf.height)
    }

    super.init(
      contentRect: windowRect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    self.backgroundColor = NSColor.clear
    self.isOpaque = false
    self.hasShadow = false
    self.level = NSWindow.Level.floating
    self.ignoresMouseEvents = true
    // An effect belongs to a screen rather than to a space. Without this the window stays on the
    // space it was made on, so switching to a full-screen app takes the glow away — which is
    // precisely the notification most worth not missing.
    self.collectionBehavior = [.canJoinAllSpaces, .stationary]

    glowView = GlowView(frame: windowRect, edge: edge)
    self.contentView = glowView
  }

  func update(_ glows: [ResolvedGlow], pulse: PulseSettings) {
    glowView.setPulse(pulse)
    glowView.updateAvailable(glows)
  }

  /// `orderFrontRegardless`, never `makeKeyAndOrderFront`: Ping owns no input, and an effect that
  /// asked to be key would be asking for some. A borderless window declines key status on its own,
  /// so this is the decision rather than the style mask being relied on to make it.
  func showGlow() {
    self.orderFrontRegardless()
  }

  func hideGlow() {
    self.orderOut(nil)
  }
}
