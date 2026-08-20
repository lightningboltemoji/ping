//
//  Color.swift
//  PingUI
//
//  The one place a config color becomes an `NSColor`. Everything below this target deals
//  in `RGBA`, which is what keeps the resolver testable.
//

import AppKit
import PingConfig

extension RGBA {
  public var nsColor: NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }
}

extension PingConfig.PingColor {
  public var nsColor: NSColor { rgba.nsColor }
}
