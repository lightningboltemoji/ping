import Testing

@testable import PingConfig

/// The table and the reader are two lists of the same keys, and the whole risk of having a table
/// at all is that they drift. A reader that *ran* the table could not drift; Ping's is hand-written,
/// because the same five glow keys are read at four depths and a flat table cannot say that. So the
/// two are pinned together here instead: every entry is written into a document and read back
/// through the real reader.
@Suite("Settings table")
struct ConfigSchemaTests {

  /// A value that is *not* this setting's default, so writing it produces a line to find.
  ///
  /// Halfway to the far end of the range rather than at it, because two of these settings are
  /// jointly constrained — `min-opacity` may not pass `max-opacity` — and a sweep that drove every
  /// number to its bound would be testing that constraint rather than the table. It is tested on
  /// its own below.
  private func offDefault(_ setting: Setting) -> TOMLValue {
    switch setting.kind {
    case .toggle:
      return .bool(!(setting.defaultValue.spelled == "true"))
    case .number(let bound, _):
      let current = Double(setting.defaultValue.spelled) ?? bound.lowerBound
      let far =
        abs(current - bound.lowerBound) > abs(current - bound.upperBound)
        ? bound.lowerBound : bound.upperBound
      let midway = (current + far) / 2
      return bound.isIntegral ? .number(midway.rounded()) : .number(midway)
    case .choice(let words):
      let other = words.first { "\"\($0)\"" != setting.defaultValue.spelled }
      return .string(other ?? words[0])
    case .color:
      return .string(setting.defaultValue.spelled == "\"red\"" ? "blue" : "red")
    }
  }

  @Test("every setting round-trips through the real reader")
  func roundTrip() throws {
    for setting in Setting.all {
      let wanted = offDefault(setting)
      #expect(!setting.isDefault(wanted), "\(setting.key) has no off-default value to write")

      var document = try ConfigDocument<Config>("")
      try document.set(setting, to: wanted)

      // It landed in the file...
      #expect(
        document.rendered.contains(wanted.spelled),
        "\(setting.key) did not reach the file: \(document.rendered)")
      // ...and the reader put it where the table says it lives.
      #expect(
        setting.value(in: document.config).spelled == wanted.spelled,
        "\(setting.key) read back as \(setting.value(in: document.config).spelled)")
    }
  }

  @Test("writing a default takes the line back out")
  func defaultUnsets() throws {
    for setting in Setting.all {
      var document = try ConfigDocument<Config>("")
      try document.set(setting, to: offDefault(setting))
      #expect(document.rendered != "")
      try document.set(setting, to: setting.defaultValue)
      #expect(
        !document.rendered.contains(setting.name),
        "\(setting.key) left a line saying what Ping already does: \(document.rendered)")
    }
  }

  /// The `[glow]` defaults are the reason this is not automatic: their fields are `Optional`, and
  /// an unwritten one has to read back as the built-in the cascade starts from rather than as
  /// nothing.
  @Test("a glow default reads as the built-in when the file is silent")
  func glowDefaultsReadAsBuiltin() throws {
    let empty = Config()
    let glow = Setting.all(in: .glow).filter { $0.table == ["glow"] }
    #expect(glow.count == 5)
    for setting in glow {
      #expect(
        setting.isDefault(in: empty), "\(setting.key) is not at its default in an empty config")
    }
    #expect(Setting.setting(for: ["glow", "color"])?.value(in: empty).spelled == "\"green\"")
    #expect(Setting.setting(for: ["glow", "edge"])?.value(in: empty).spelled == "\"bottom\"")
  }

  @Test("a value outside its bound is refused with the bound in the message")
  func boundsRefused() throws {
    var document = try ConfigDocument<Config>("")
    let size = try #require(Setting.setting(for: ["glow", "size"]))
    let error = #expect(throws: ConfigSyntaxError.self) {
      try document.set(size, to: .number(0.1))
    }
    #expect(error?.message == "'glow.size' must be between 0.25 and 1.0, got 0.1")
    #expect(document.rendered == "")
  }

  /// The direction that can silently drift. The other one cannot: a key in the example that the
  /// table does not know is an unknown key, and `ConfigExampleTests` already parses the example.
  @Test("the example config writes every setting the table describes")
  func exampleShowsEverySetting() throws {
    let document = try ConfigDocument<Config>(ConfigExample.text)
    for setting in Setting.all {
      #expect(
        document.names(under: setting.table).contains(setting.name),
        "the example never writes '\(setting.key)'")
    }
  }

  /// A constraint across two keys, which a table of independent entries cannot carry — so the
  /// reader keeps it, and an edit that breaks it is refused with the document untouched. That is
  /// what a settings window shows in its diagnostics bar rather than applying.
  @Test("a cross-key constraint refuses the edit and keeps the file")
  func crossKeyConstraint() throws {
    var document = try ConfigDocument<Config>("[glow.pulse]\nmin-opacity = 0.25\n")
    let maximum = try #require(Setting.setting(for: ["glow", "pulse", "max-opacity"]))
    let error = #expect(throws: ConfigSyntaxError.self) {
      try document.set(maximum, to: .number(0.1))
    }
    #expect(error?.message == "'glow.pulse.min-opacity' must not be above 'glow.pulse.max-opacity'")
    #expect(document.rendered == "[glow.pulse]\nmin-opacity = 0.25\n")
  }

  @Test("every setting explains itself in one sentence")
  func legends() {
    for setting in Setting.all {
      #expect(setting.help.hasSuffix("."), "\(setting.key)'s help is not a sentence")
      #expect(!setting.label.isEmpty)
      if case .toggle = setting.kind {
        #expect(setting.legend == nil)
      } else {
        #expect(setting.legend?.isEmpty == false, "\(setting.key) has no legend")
      }
    }
  }
}
