//
//  ConfigTable.swift
//  PingConfig
//
//  The schema's half of the seam: a cursor over one parsed table, and the typed readers the
//  schema pulls keys out of it with.
//
//  Reading is *taking*. Each model takes the keys it knows and then asks what is left; whatever
//  is left is a key the schema does not know, reported by line. There is exactly
//  one list of known keys and it is `ConfigReader.swift`.
//
//  Kept apart from `TOML.swift` on purpose. That file is the grammar — what a file may say — and
//  it stays free of Ping's opinions: colours, kebab-case leniency, the ranges a slider can reach.
//  Those live here, where a cursor also carries the two things a diagnostic needs and a grammar has
//  no business holding: where in the document this table sits, and the sink every table under it
//  reports through.
//

/// One table of a parsed document, and the reading position in it.
///
/// Not `Sendable`: it is a transient parse artifact sharing a diagnostic sink. `Config` is the
/// value that crosses threads.
public struct ConfigTable {

  /// Where this table sits in the document. Empty at the root. Prefixed onto every diagnostic, so
  /// `color` read four levels down is still named `apps.Slack.glow.dot.color`.
  public let path: TOMLKey

  /// This table's own contents, as the grammar read them. Taking is destructive.
  var table: TOMLTable
  let sink: DiagnosticSink

  init(path: TOMLKey, table: TOMLTable, sink: DiagnosticSink) {
    self.path = path
    self.table = table
    self.sink = sink
  }

  /// A cursor on a whole document.
  init(root: TOMLTable) {
    self.init(path: TOMLKey([]), table: root, sink: DiagnosticSink())
  }

  /// The line this table was declared on — its header, or the `{` it opened at.
  public var line: Int { table.line }

  public var isEmpty: Bool { table.entries.isEmpty }

  /// Diagnostics raised anywhere under the document this table came from.
  public var diagnostics: [ConfigDiagnostic] { sink.diagnostics }

  func note(_ message: String, line: Int) {
    sink.note(message, line: line)
  }

  // MARK: - Taking scalars
  //
  // One line each: take the value, then hand it to the reader that knows what a legal one is.
  // Those readers are on `TOMLValue` rather than here, so a key read out of a file and a value
  // a settings window produced are refused by the same code with the same sentence — which is
  // what `ConfigSchema`'s codecs need in order not to restate any of it.

  public mutating func takeString(_ key: String) throws -> String? {
    try table.take(key)?.string(path.appending(key))
  }

  public mutating func takeBool(_ key: String) throws -> Bool? {
    try table.take(key)?.bool(path.appending(key))
  }

  public mutating func takeInt(_ key: String, in bounds: ClosedRange<Int>? = nil) throws -> Int? {
    try table.take(key)?.integer(path.appending(key), in: bounds)
  }

  public mutating func takeDouble(
    _ key: String, in bounds: ClosedRange<Double>? = nil
  ) throws -> Double? {
    try table.take(key)?.number(path.appending(key), in: bounds)
  }

  /// A lowercase kebab-case enum value. `topCenter` is accepted with a diagnostic naming the
  /// spelling it moved to, for anyone hand-migrating — leniency a file gets and a control
  /// does not need, which is why the note is passed in rather than built in.
  public mutating func takeEnum<E: RawRepresentable & CaseIterable>(
    _ key: String, as type: E.Type
  ) throws -> E? where E.RawValue == String {
    // The sink rather than `self`: an optional closure parameter escapes, and `self` is mutating.
    let sink = self.sink
    return try table.take(key)?.word(
      path.appending(key), as: type, note: { sink.note($0, line: $1) })
  }

  /// A colour: one of the eight names, or `#rrggbb` / `#rrggbbaa`.
  public mutating func takeColor(_ key: String) throws -> PingColor? {
    try table.take(key)?.color(path.appending(key))
  }

  // MARK: - Taking tables

  /// The subtable at `key`, and everything under it — `nil` when the document never mentions it,
  /// which is how "the app did not subscribe to this effect" is spelled.
  ///
  /// - Throws: when `key` holds a value instead. `glow = "green"` is a mistake about `glow`, and
  ///   saying so beats letting it fall through to "unknown key" as if the name were the typo.
  public mutating func takeTable(_ key: String) throws -> ConfigTable? {
    if let child = table.takeChild(key) {
      return ConfigTable(path: path.appending(key), table: child, sink: sink)
    }
    if let value = table.value(at: TOMLKey([key])) {
      throw ConfigSyntaxError.badValue(
        line: value.line, key: path.appending(key),
        message: "expects a table, got \(value.typeName)")
    }
    return nil
  }

  /// Every table one segment below `key`, keyed by a name the *user* invented — `[apps.Slack]`,
  /// `[apps."Google Chrome"]` — in the order the file introduces them.
  ///
  /// `key` itself is accepted, so a bare `[apps]` is not a mistake; anything under it that is not
  /// a table is left where it is, and reported as the unknown key it is.
  public mutating func takeTables(under key: String) -> [(name: String, table: ConfigTable)] {
    table.takeGrandchildTables(key).map { name, child in
      (name, ConfigTable(path: path.appending(key).appending(name), table: child, sink: sink))
    }
  }

  // MARK: - What's left

  /// Whatever the schema did not take is a key the schema does not know. Earliest line
  /// first, so the complaint names the first mistake rather than an arbitrary one.
  public func reportUnknownKeys() throws {
    guard let first = table.leftovers.first else { return }
    throw ConfigSyntaxError.unknownKey(
      line: first.line, key: path.appending(contentsOf: first.key))
  }

  // MARK: - Helpers

  static func kebabCased(_ text: String) -> String {
    var out = ""
    for character in text {
      if character.isUppercase {
        out.append("-")
        out.append(Character(character.lowercased()))
      } else {
        out.append(character)
      }
    }
    return out
  }
}

//
// What a legal value is, asked of a value on its own. Every reader here names the key it was
// given rather than looking one up: the same complaint has to serve a line of a file, where the
// key is where it was written, and a control, where the key is what the control edits.

extension TOMLValue {

  /// How this value's kind is named in a diagnostic. Finer than "a number": a schema that
  /// refuses `size = 1` wants to say which of the two numeric types the file wrote.
  var typeName: String {
    switch payload {
    case .bool: "a boolean"
    case .integer: "an integer"
    case .float: "a float"
    case .string: "a string"
    case .dateTime: "a date"
    case .array: "an array"
    case .table: "a table"
    }
  }

  private func mismatch(_ key: TOMLKey, expected: String) -> ConfigSyntaxError {
    .badValue(line: line, key: key, message: "expects \(expected), got \(typeName)")
  }

  func string(_ key: TOMLKey) throws -> String {
    guard case .string(let text) = payload else { throw mismatch(key, expected: "a string") }
    return text
  }

  func bool(_ key: TOMLKey) throws -> Bool {
    guard case .bool(let flag) = payload else { throw mismatch(key, expected: "a boolean") }
    return flag
  }

  func integer(_ key: TOMLKey, in bounds: ClosedRange<Int>? = nil) throws -> Int {
    guard case .integer(let integer) = payload, let number = Int(exactly: integer) else {
      throw mismatch(key, expected: "an integer")
    }
    // Refused with the bound in the message rather than clamped: a slider that cannot reach a
    // value beats a file that doesn't mean what it says.
    if let bounds, !bounds.contains(number) {
      throw ConfigSyntaxError.badValue(
        line: line, key: key,
        message: "must be between \(bounds.lowerBound) and \(bounds.upperBound), got \(number)")
    }
    return number
  }

  func number(_ key: TOMLKey, in bounds: ClosedRange<Double>? = nil) throws -> Double {
    // `1` is a legal spelling of `1.0`, and the one place the schema does not care which of the
    // two numeric types the file wrote.
    guard let number = asDouble else { throw mismatch(key, expected: "a number") }
    if let bounds, !bounds.contains(number) {
      throw ConfigSyntaxError.badValue(
        line: line, key: key,
        message: "must be between \(TOMLValue.spell(bounds.lowerBound, decimal: true)) and "
          + "\(TOMLValue.spell(bounds.upperBound, decimal: true)), "
          + "got \(TOMLValue.spell(number, decimal: true))")
    }
    return number
  }

  /// One word from a fixed vocabulary. **The type is the vocabulary**: the legal words are read
  /// off `allCases`, so a case added to the enum is accepted, named in the diagnostic and offered
  /// by a control with nothing here to update.
  func word<E: RawRepresentable & CaseIterable>(
    _ key: TOMLKey, as type: E.Type, note: ((String, Int) -> Void)? = nil
  ) throws -> E where E.RawValue == String {
    let raw = try string(key)
    if let match = E(rawValue: raw) { return match }

    let kebab = ConfigTable.kebabCased(raw)
    if let note, kebab != raw, let match = E(rawValue: kebab) {
      note("'\(key)' should be \"\(kebab)\", not \"\(raw)\"", line)
      return match
    }

    let known = E.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
    throw ConfigSyntaxError.badValue(
      line: line, key: key, message: "does not take \"\(raw)\"; expected one of \(known)")
  }

  func color(_ key: TOMLKey) throws -> PingColor {
    guard case .string(let raw) = payload else { throw mismatch(key, expected: "a color") }
    guard let color = PingColor(raw) else {
      throw ConfigSyntaxError.badValue(
        line: line, key: key,
        message: "does not take \"\(raw)\"; expected a color name "
          + "(\(NamedColor.allCases.map(\.rawValue).joined(separator: ", "))) or "
          + "\"#rrggbb\" / \"#rrggbbaa\"")
    }
    return color
  }
}
