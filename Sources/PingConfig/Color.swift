//
//  Color.swift
//  PingConfig
//

/// Straight sRGB components, 0...1. `PingConfig` stops here: the conversion to `NSColor`
/// lives in `PingUI`, which is what keeps the resolver testable.
public struct RGBA: Equatable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}

/// The eight names Ping has always had, at the values it has always drawn them.
///
/// The historical `NSColor`s carried `alpha: 0.9`, but every path replaced it with the
/// app's `opacity` before drawing, so the 0.9 was never visible. Alpha is `opacity`'s job
/// now, and a config that leaves `opacity` at its default renders identically.
public enum NamedColor: String, CaseIterable, Sendable {
  case red, orange, yellow, green, blue, purple, pink, white

  public var rgba: RGBA {
    switch self {
    case .red: RGBA(red: 1.0, green: 0.2, blue: 0.2)
    case .orange: RGBA(red: 1.0, green: 0.6, blue: 0.0)
    case .yellow: RGBA(red: 1.0, green: 0.9, blue: 0.0)
    case .green: RGBA(red: 0.0, green: 0.8, blue: 0.2)
    case .blue: RGBA(red: 0.2, green: 0.4, blue: 1.0)
    case .purple: RGBA(red: 0.6, green: 0.2, blue: 1.0)
    case .pink: RGBA(red: 1.0, green: 0.3, blue: 0.6)
    case .white: RGBA(red: 1.0, green: 1.0, blue: 1.0)
    }
  }
}

/// A color as the file spells it: one of the names, or `#rrggbb` / `#rrggbbaa`.
/// The spelling is kept so the GUI writes back what the user wrote.
public enum PingColor: Equatable, Sendable {
  case named(NamedColor)
  case hex(RGBA)

  public init?(_ raw: String) {
    if let name = NamedColor(rawValue: raw) {
      self = .named(name)
      return
    }
    guard raw.hasPrefix("#") else { return nil }
    let digits = raw.dropFirst()
    guard digits.count == 6 || digits.count == 8,
      digits.allSatisfy(\.isHexDigit),
      let packed = UInt32(digits, radix: 16)
    else { return nil }

    let hasAlpha = digits.count == 8
    let shift = hasAlpha ? 8 : 0
    func channel(_ byte: Int) -> Double {
      Double((packed >> UInt32(byte * 8 + shift)) & 0xFF) / 255.0
    }
    self = .hex(
      RGBA(
        red: channel(2), green: channel(1), blue: channel(0),
        alpha: hasAlpha ? Double(packed & 0xFF) / 255.0 : 1.0))
  }

  public var rgba: RGBA {
    switch self {
    case .named(let name): name.rgba
    case .hex(let rgba): rgba
    }
  }

  /// How this color is written back into the file.
  public var written: String {
    switch self {
    case .named(let name):
      return name.rawValue
    case .hex(let rgba):
      func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
      let base = String(
        format: "#%02x%02x%02x", byte(rgba.red), byte(rgba.green), byte(rgba.blue))
      return rgba.alpha == 1.0 ? base : base + String(format: "%02x", byte(rgba.alpha))
    }
  }
}
