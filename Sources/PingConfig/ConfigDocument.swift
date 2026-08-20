//
//  ConfigDocument.swift
//  PingConfig
//
//  The config file as something you can edit — the writer half of `PingConfig`, and the reason
//  `TOML.swift` carries spans at all. Generic over the model it reads, and able to edit inside
//  braces.
//
//  A settings window reads a `Config` out of a file and writes single values back into it. What it
//  must not do is *rewrite* the file: Ping is configured by hand, and the comments, the ordering
//  and the blank lines that group one app from the next are the author's work. A `Config → TOML`
//  serializer would be a tenth of this code and would eat all three. So nothing here formats. An
//  edit splices over the stretch of text one value occupies, or adds one line, and every other byte
//  stays exactly where the author left it — including the spaces around a `=` and whether a number
//  two lines up was typed `1` or `1.0`.
//
//  **One edit moves lines, and it says so.** `expand` turns `glow = { … }` into a `[…glow]` header
//  block, which is what the GUI reaches for when a badge-kind override arrives. Everything
//  else here disturbs no other byte, and that asymmetry is stated rather than discovered.
//
//  **No I/O.** `rendered` is a `String`; the caller writes it.
//

/// A config file, its text and its parse held together, so a value can be changed in place. Every
/// field is a `let`: an edit replaces the whole document rather than patching one, which is what
/// makes the text, the spans and the model unable to disagree.
public struct ConfigDocument<Model: ConfigModel> {

  /// The file's text. `rendered` is this and nothing else, which makes round-trip identity a
  /// property of the design rather than one the tests have to keep true.
  private let text: String
  /// The same text parsed, kept whole: the schema consumes a *copy*, so the spans survive the read.
  private let table: TOMLTable
  /// The terminator this file's lines end with. Per file, not per line — Swift reads `"\r\n"` as one
  /// grapheme, so a CRLF file arrives as CRLF lines, and any line this adds has to match.
  private let terminator: String

  /// The document read as a model. In step with every edit: one the schema refuses throws rather
  /// than landing, so this is always the reading of `rendered`.
  public let config: Model
  /// What the schema accepted but wanted to say out loud about — carried alongside, never fatal.
  public let diagnostics: [ConfigDiagnostic]

  /// Read a config file, remembering where every value in it was written.
  ///
  /// - Throws: `ConfigSyntaxError` — exactly what `Config.parse` throws of the same text, from the
  ///   same code. A document that cannot be read is one a GUI must not offer to write.
  public init(_ text: String) throws {
    let table = try TOMLTable.parse(text)
    var consumable = ConfigTable(root: table)
    self.config = try Model(reading: &consumable)
    self.diagnostics = consumable.diagnostics
    self.table = table
    self.text = text
    self.terminator = text.first(where: \.isNewline).map(String.init) ?? "\n"
  }

  /// The file as it now stands, for the caller to write.
  public var rendered: String { text }

  /// The keys the file writes directly under `path`, spelled the way it spells them, in file order.
  public func names(under path: TOMLKey) -> [String] {
    table.names(under: path)
  }

  // MARK: - Editing

  /// Set `key` to `value` — splicing over the value already on its line, or writing the key where
  /// the file has no line for it yet.
  ///
  /// - Throws: `ConfigSyntaxError` when the result is not a config the schema accepts — a number
  ///   outside its range, a key it doesn't know. The document is untouched, so a refused edit costs
  ///   nothing, and the complaint is the same sentence the file itself would have produced.
  public mutating func set(_ key: TOMLKey, to value: TOMLValue) throws {
    var edited = text
    if let span = table.span(of: key) {
      edited.replaceSubrange(span.value, with: value.spelled)
    } else if let existing = table.child(at: key) {
      // The name is already a table. Asking for the table that is already there is nothing to do;
      // asking for anything else is a mistake about the name rather than about the value.
      guard case .table(let contents) = value.payload, contents.entries.isEmpty else {
        throw ConfigSyntaxError.badValue(
          line: existing.line, key: key,
          message: "is written as a table; set a key inside it instead")
      }
      return
    } else {
      try insert(key, value, into: &edited)
    }
    try commit(edited)
  }

  /// Unset `key`, taking its whole statement with it — **its trailing comment included**, and every
  /// line of a multi-line value. A key the file doesn't write is left alone.
  ///
  /// `key` may name a whole table, which is how an app stops being subscribed to an effect: an
  /// app's `glow` is not a value with a default to fall back to, it is its presence in the file.
  /// Then everything the table occupies goes — the `[header]`'s run of lines and every
  /// deeper header under it, or the one line it was written on between braces.
  ///
  /// Between braces there is no line to take, so the `{ … }` is written out again without that
  /// pair. Removing the last one leaves `{}` rather than deleting the line: the app is still
  /// subscribed, it just has nothing to say about the effect.
  ///
  /// - Throws: as `set` does. Dropping a key restores its default, which the schema accepts on its
  ///   own.
  public mutating func remove(_ key: TOMLKey) throws {
    // The *parent*, not the key: an inline table is written inside its parent's braces, and asking
    // about the key itself would answer with its own braces, which is the thing being removed.
    let enclosing = key.split.flatMap { table.enclosingInline(of: $0.parent) }
    var edited = text

    if let (path, inline) = enclosing, let name = key.dropping(prefix: path) {
      guard inline.pairs.contains(where: { $0.key == name }) else { return }
      edited.replaceSubrange(
        inline.braces, with: braces(inline.pairs.filter { $0.key != name }.map(text: text)))
    } else if let span = table.span(of: key) {
      edited.removeSubrange(withTerminator(span.statement))
    } else if table.child(at: key) != nil {
      // Back to front, so the ranges ahead of the one being cut are still the ranges they were.
      for stretch in table.occupied(by: key).reversed() {
        edited.removeSubrange(withBlankLine(after: withTerminator(stretch)))
      }
    } else {
      return
    }
    try commit(edited)
  }

  /// Rewrite `key`'s inline table as a `[header]` block of its own.
  ///
  /// **The one edit that moves lines.** TOML's rule is that an inline table cannot be reopened by a
  /// later header, so a GUI that wants to write `[apps.Messages.glow.dot]` under an app whose glow
  /// is a `{ … }` has to take the braces apart first. The block goes directly after the run
  /// of lines it was written in, so an app's settings stay together.
  ///
  /// Each pair becomes a line of its own, as the text the author typed. A key the file doesn't write
  /// between braces is left alone.
  ///
  /// - Throws: `ConfigSyntaxError` when there is nowhere for the block to go — an inline table
  ///   nested inside another one, or one whose enclosing table the file never declared as a header.
  ///   The document is untouched when it throws.
  public mutating func expand(_ key: TOMLKey) throws {
    guard let child = table.child(at: key), let inline = child.inline,
      let statement = inline.statement, let (parent, _) = key.split
    else { return }

    guard table.enclosingInline(of: parent) == nil else {
      throw ConfigSyntaxError.badValue(
        line: child.line, key: key,
        message: "cannot be expanded — it is written inside another inline table")
    }
    let insertAt: String.Index
    if parent.isEmpty {
      // A table header may not precede a top-level key, so the block goes at the end of the file
      // rather than where the key it replaces was.
      insertAt = text.endIndex
    } else if let extent = table.extent(of: parent) {
      insertAt = lineBreak(after: extent.upperBound)
    } else {
      throw ConfigSyntaxError.badValue(
        line: child.line, key: key,
        message: "cannot be expanded — '\(parent)' is not written as a table header")
    }

    let removed = withTerminator(statement)
    let stop = max(insertAt, removed.upperBound)
    // Whatever followed the closing brace is the author's comment about this effect, so it moves to
    // the header rather than leaving with the line it was written on.
    let trailing = String(text[inline.braces.upperBound..<statement.upperBound])
    let block =
      terminator + "[\(key)]" + trailing + terminator
      + inline.pairs.map(text: text).map { $0 + terminator }.joined()

    try commit(
      String(text[text.startIndex..<removed.lowerBound]) + String(text[removed.upperBound..<stop])
        + block + String(text[stop...]))
  }

  /// Take the edit, by reading the edited text from scratch. Spans move when text is spliced, so the
  /// alternative is bookkeeping to keep the parse in step with the file, and there is no version of
  /// that which cannot fall out of step. Reading again cannot: it is where `config` comes from and
  /// where the next edit's spans come from, both at once, and a config file is a page long.
  ///
  /// An assignment, so a document whose edit the schema refuses is left exactly as it was.
  private mutating func commit(_ edited: String) throws {
    self = try ConfigDocument(edited)
  }

  // MARK: - Where a new key goes
  //
  // Deterministic, so writing the same change twice writes the same file.

  /// A key the file doesn't set yet: inside the braces it belongs between, at the end of its
  /// `[table]`'s run of key lines, or under a header appended for it.
  private func insert(_ key: TOMLKey, _ value: TOMLValue, into edited: inout String) throws {
    guard let (parent, name) = key.split else { return }

    // Written between braces? Then the braces own the text, and the new pair carries however much
    // of the path they don't already cover — `dot.enabled = false`, which is a dotted key inside an
    // inline table and so still TOML the file can be read back from.
    if let (path, inline) = table.enclosingInline(of: parent),
      let relative = key.dropping(prefix: path)
    {
      let pair = "\(relative) = " + value.spelled
      edited.replaceSubrange(
        inline.braces, with: braces(inline.pairs.map(text: text) + [pair]))
      return
    }

    let statement = TOMLTable.spell(key: name) + " = " + value.spelled
    if let extent = table.extent(of: parent) {
      // The run ends at the last key line, not at the blank line or comment that may follow it, so
      // the new key joins the table rather than the gap after it.
      edited.insert(contentsOf: terminator + statement, at: extent.upperBound)
    } else if parent.isEmpty {
      // A top-level key has to precede every header — TOML's rule, not a preference.
      if let first = table.firstHeaderStart {
        edited.insert(contentsOf: statement + terminator + terminator, at: first)
      } else {
        append(statement, to: &edited)
      }
    } else if let existing = table.child(at: parent), existing.origin == .dotted {
      // A table a dotted key made is closed to any later header — TOML's rule — so there is nowhere
      // to put this line. Said here, because otherwise the header is written, the re-parse refuses
      // it, and the complaint the user sees is "'…' is set twice" about a line they never wrote.
      throw ConfigSyntaxError.badValue(
        line: existing.line, key: key,
        message: "cannot be set — '\(parent)' is written as a dotted key, which a table header may "
          + "not reopen; write it as '[\(parent)]' instead")
    } else {
      append("[\(parent)]" + terminator + statement, to: &edited)
    }
  }

  /// At the end of the file, a blank line clear of whatever was there. A file that didn't end in a
  /// terminator gains one, which is the one byte an append moves that it wasn't asked to.
  private func append(_ block: String, to edited: inout String) {
    if let last = edited.last, !last.isNewline { edited += terminator }
    if !edited.isEmpty { edited += terminator }
    edited += block + terminator
  }

  /// An inline table written out again from its pairs. A comment cannot appear between braces — the
  /// `#` would swallow the closing one — so a `{ … }` holds no authored content beyond its pairs,
  /// and re-rendering it loses nothing but the spacing *between* them.
  private func braces(_ pairs: [String]) -> String {
    pairs.isEmpty ? "{}" : "{ " + pairs.joined(separator: ", ") + " }"
  }

  /// A statement's range grown to swallow the terminator that ends it — or, on a last line that has
  /// none, the terminator before it, so removing it doesn't leave a blank line in its place.
  private func withTerminator(_ statement: Range<String.Index>) -> Range<String.Index> {
    if statement.upperBound < text.endIndex, text[statement.upperBound].isNewline {
      return statement.lowerBound..<text.index(after: statement.upperBound)
    }
    if statement.lowerBound > text.startIndex {
      return text.index(before: statement.lowerBound)..<statement.upperBound
    }
    return statement
  }

  /// A block's range grown to swallow the blank line that separated it from what follows, so
  /// taking a `[table]` out doesn't leave the gap that was around it. Only a *blank* line: a
  /// comment after a block is somebody's note about what comes next.
  private func withBlankLine(after block: Range<String.Index>) -> Range<String.Index> {
    var cursor = block.upperBound
    while cursor < text.endIndex, text[cursor] == " " || text[cursor] == "\t" {
      cursor = text.index(after: cursor)
    }
    guard cursor < text.endIndex, text[cursor].isNewline else { return block }
    return block.lowerBound..<text.index(after: cursor)
  }

  /// The start of the line after the one `index` sits on — where a block of new lines goes so that
  /// it begins on a line of its own.
  private func lineBreak(after index: String.Index) -> String.Index {
    var cursor = index
    while cursor < text.endIndex, !text[cursor].isNewline { cursor = text.index(after: cursor) }
    return cursor < text.endIndex ? text.index(after: cursor) : cursor
  }
}

extension [TOMLInline.Pair] {
  /// The pairs as the author wrote them. Their own text, never their values re-spelled: a pair this
  /// edit doesn't touch keeps whatever was typed.
  fileprivate func map(text: String) -> [String] {
    map { String(text[$0.text]) }
  }
}

//
// The half of the document that needs to know what a *setting* is, which is only ever `Config`.

extension ConfigDocument where Model == Config {

  /// Record `value` for `setting` — which is `set` **or `remove`**, because setting something to
  /// its default *unsets* it: an absent key already says what the default says, and a file that
  /// writes it down pins it against ever changing.
  ///
  /// The fork lives here rather than at a call site because a `Setting` is what knows its own
  /// default and a bare key does not — and a rule about what a file should contain must not be one
  /// two consumers could quietly disagree about.
  ///
  /// The glow defaults make this the difference between a file that grows every time a window is
  /// opened and one that doesn't: their `Setting`s read through the built-in the cascade starts
  /// from, so choosing green in the Glow tab writes no line at all.
  ///
  /// - Throws: as `set` and `remove` do.
  public mutating func set(_ setting: Setting, to value: TOMLValue) throws {
    if setting.isDefault(value) {
      try remove(setting.key)
    } else {
      try set(setting.key, to: value)
    }
  }
}
