//
//  Diagnostics.swift
//  PingConfig
//

/// A refusal, naming the line it happened on.
///
/// Rendered as `line N: message`; `ping validate` prefixes the path to make it
/// `path:N: message`, which editors and CI already know how to jump to.
public struct ConfigSyntaxError: Error, Equatable, Sendable, CustomStringConvertible {
  public var line: Int
  public var message: String

  public init(line: Int, message: String) {
    self.line = line
    self.message = message
  }

  public var description: String { "line \(line): \(message)" }

  // The four things that go wrong, as the sentences they are shown as. Named rather than spelled at
  // each throw site so the same mistake reads the same way wherever it is caught — the grammar
  // (`TOML.swift`) raises the first two, the schema the last two.

  /// The text isn't the grammar: a malformed header, an unterminated string, a value that isn't one.
  static func syntax(line: Int, message: String) -> ConfigSyntaxError {
    ConfigSyntaxError(line: line, message: message)
  }

  /// The same key was set twice — refused rather than last-wins.
  static func duplicateKey(line: Int, key: TOMLKey) -> ConfigSyntaxError {
    ConfigSyntaxError(line: line, message: "'\(key)' is set twice")
  }

  /// A key, or a whole table, the schema doesn't know — almost always a typo.
  static func unknownKey(line: Int, key: TOMLKey) -> ConfigSyntaxError {
    ConfigSyntaxError(line: line, message: "unknown key '\(key)'")
  }

  /// The key exists but the value is the wrong kind, or outside the range it may take.
  static func badValue(line: Int, key: TOMLKey, message: String) -> ConfigSyntaxError {
    ConfigSyntaxError(line: line, message: "'\(key)' \(message)")
  }
}

/// Something accepted, but worth saying out loud — a spelling that still works but has
/// moved. Never fatal; collected while reading and reported alongside the config.
public struct ConfigDiagnostic: Equatable, Sendable, CustomStringConvertible {
  public var line: Int
  public var message: String

  public init(line: Int, message: String) {
    self.line = line
    self.message = message
  }

  public var description: String { "line \(line): \(message)" }
}

/// Shared by a table and every sub-table taken out of it, so a diagnostic raised deep in
/// `apps.X.glow.dot` still arrives at the top.
final class DiagnosticSink {
  var diagnostics: [ConfigDiagnostic] = []

  func note(_ message: String, line: Int) {
    diagnostics.append(ConfigDiagnostic(line: line, message: message))
  }
}
