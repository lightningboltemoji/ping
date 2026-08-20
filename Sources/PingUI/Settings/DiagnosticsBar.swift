//
//  DiagnosticsBar.swift
//  PingUI
//
//  What the file has to say, at the bottom of the window where it can always be seen.
//
//  Four things, in the order they matter: the file changed underneath an unsaved draft, the last
//  edit was refused, the file wouldn't parse at all, and a spelling that still works but has moved.
//  Each is the file's own sentence — the same one `ping validate` prints — because a second wording
//  for the same complaint is a second thing to keep true.
//

import PingConfig
import SwiftUI

struct DiagnosticsBar: View {
  @Bindable var model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let conflict = model.conflict {
        // Held rather than applied: throwing away typing is worse than either version of the file,
        // so the two ways out are offered and Save waits.
        Banner(icon: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90", tint: .orange) {
          HStack {
            Text(conflict)
            Spacer()
            Button("Reload") { model.reloadFromDisk() }
            Button("Keep mine") { model.overwrite() }
          }
        }
      }
      if let refusal = model.refusal {
        Banner(icon: "xmark.octagon", tint: .red) { Text(refusal) }
      }
      if let failure = model.openFailure {
        Banner(icon: "exclamationmark.triangle", tint: .red) { Text(failure) }
      }
      ForEach(model.diagnostics.indices, id: \.self) { index in
        Banner(icon: "info.circle", tint: .secondary) {
          Text(model.diagnostics[index].description)
        }
      }
    }
  }
}

private struct Banner<Content: View>: View {
  let icon: String
  let tint: Color
  @ViewBuilder let content: Content

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: icon).foregroundStyle(tint)
      content
    }
    .font(.callout)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
  }
}
