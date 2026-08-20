//
//  SettingsForm.swift
//  PingUI
//
//  Three tabs, no three tab files: General, Glow and Shelf are the sections of the settings table
//  (`ConfigSchema.swift`), and a section is laid out by walking it.
//
//  **One control per `Kind`, not one per setting.** A setting added to the table appears here with
//  nothing to write, which is the whole reason the table exists — the alternative is a second list
//  of the same keys, drifting. The one surface this cannot lay out is `apps.*`, which is not a list
//  of settings at all and has a panel written for it.
//

import PingConfig
import SwiftUI

struct SettingsForm: View {
  let section: Setting.Section
  @Bindable var model: SettingsModel

  private var settings: [Setting] { Setting.all(in: section) }

  var body: some View {
    Form {
      Section {
        ForEach(settings.filter { !$0.isAdvanced }, id: \.key) { setting in
          SettingRow(setting: setting, model: model)
        }
      }
      let advanced = settings.filter(\.isAdvanced)
      if !advanced.isEmpty {
        Section("Advanced") {
          ForEach(advanced, id: \.key) { setting in
            SettingRow(setting: setting, model: model)
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}

/// One setting, as the control its `Kind` asks for.
struct SettingRow: View {
  let setting: Setting
  @Bindable var model: SettingsModel

  var body: some View {
    switch setting.kind {
    case .toggle:
      LabeledContent {
        Toggle("", isOn: boolBinding).labelsHidden()
      } label: {
        label
      }

    case .number(let bound, let unit):
      LabeledContent {
        HStack(spacing: 8) {
          Slider(value: numberBinding(bound), in: bound.lowerBound...bound.upperBound)
            .frame(minWidth: 140)
          Text(reading(bound, unit))
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
            // Fixed, so the row doesn't twitch as the digits change under the thumb.
            .frame(width: 64, alignment: .trailing)
        }
      } label: {
        label
      }

    case .choice(let words):
      LabeledContent {
        Picker("", selection: stringBinding) {
          ForEach(words, id: \.self) { word in
            Text(word.replacingOccurrences(of: "-", with: " ").capitalized).tag(word)
          }
        }
        .labelsHidden()
        .frame(maxWidth: 200)
      } label: {
        label
      }

    case .color:
      LabeledContent {
        ColorWell(color: colorBinding)
      } label: {
        label
      }
    }
  }

  private var label: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(setting.label)
      Text(setting.help).font(.caption).foregroundStyle(.secondary)
    }
  }

  /// The value with its unit, and no more precision than the setting has: a poll interval is whole
  /// milliseconds and an opacity is a fraction.
  private func reading(_ bound: Setting.Bound, _ unit: Setting.Unit) -> String {
    let number = model.value(of: setting).asDouble ?? bound.lowerBound
    let digits = bound.isIntegral ? "%.0f" : "%.2f"
    return String(format: digits, number) + (unit.rawValue.isEmpty ? "" : " \(unit.rawValue)")
  }

  // The bindings. Each writes through `SettingsModel`, which is what makes choosing a default take
  // the line out of the file rather than write it down.

  private var boolBinding: Binding<Bool> {
    Binding(
      get: { model.value(of: setting).asBool ?? false },
      set: { model.set(setting, to: .bool($0)) })
  }

  private func numberBinding(_ bound: Setting.Bound) -> Binding<Double> {
    Binding(
      get: { model.value(of: setting).asDouble ?? bound.lowerBound },
      set: { model.set(setting, to: .number(bound.isIntegral ? $0.rounded() : $0)) })
  }

  private var stringBinding: Binding<String> {
    Binding(
      get: { model.value(of: setting).asText ?? "" },
      set: { model.set(setting, to: .string($0)) })
  }

  private var colorBinding: Binding<PingColor> {
    Binding(
      get: {
        guard let raw = model.value(of: setting).asText else { return .named(.white) }
        return PingColor(raw) ?? .named(.white)
      },
      set: { model.set(setting, to: .string($0.written)) })
  }
}

/// The eight names, and a well for anything else.
///
/// Not a bare `ColorPicker`: a colour in this file is a *name* or a hex triple, and the spelling is
/// kept so the file says `green` where the user chose green. A picker alone would turn every
/// choice into `#33cc33` the first time it was touched.
struct ColorWell: View {
  @Binding var color: PingColor

  var body: some View {
    HStack(spacing: 6) {
      ForEach(NamedColor.allCases, id: \.self) { name in
        Button {
          color = .named(name)
        } label: {
          Circle()
            .fill(Color(name.rgba.nsColor))
            .frame(width: 18, height: 18)
            .overlay(
              Circle().strokeBorder(
                color == .named(name) ? Color.primary : Color.primary.opacity(0.15),
                lineWidth: color == .named(name) ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(name.rawValue)
      }
      ColorPicker("", selection: custom, supportsOpacity: true)
        .labelsHidden()
        .help("A custom color, written as #rrggbb")
    }
  }

  private var custom: Binding<Color> {
    Binding(
      get: { Color(color.nsColor) },
      set: { picked in
        let rgb = NSColor(picked).usingColorSpace(.sRGB) ?? .white
        color = .hex(
          RGBA(
            red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent,
            alpha: rgb.alphaComponent))
      })
  }
}

/// A slider and its reading, sized so a row doesn't twitch as the digits change under the thumb.
/// Shared with the Apps panel, whose numbers are the same numbers one level deeper.
struct NumberRow: View {
  @Binding var value: Double
  let range: ClosedRange<Double>
  var isIntegral = false
  var unit: String = ""

  var body: some View {
    HStack(spacing: 8) {
      Slider(value: $value, in: range).frame(minWidth: 120)
      Text(String(format: isIntegral ? "%.0f" : "%.2f", value) + (unit.isEmpty ? "" : " \(unit)"))
        .font(.body.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 56, alignment: .trailing)
    }
  }
}
