//
//  ShelfView.swift
//  PingUI
//
//  Was `FloatingDockView`. We *read* the macOS Dock, so the old name was overloaded in the
//  one place it mattered most.
//

import PingConfig
import PingCore
import SwiftUI

struct ShelfView: View {
  let settings: ShelfSettings
  let items: [ShelfItem]
  let icons: [String: NSImage]

  var body: some View {
    if !items.isEmpty {
      HStack(spacing: 12) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          VStack(spacing: 4) {
            let iconImage = Group {
              if let icon = icons[item.appName] {
                Image(nsImage: icon)
                  .resizable()
                  .frame(width: settings.iconSize, height: settings.iconSize)
              } else {
                Image(systemName: "app.fill")
                  .resizable()
                  .frame(width: settings.iconSize, height: settings.iconSize)
                  .foregroundStyle(.secondary)
              }
            }
            if settings.showBadges {
              iconImage.overlay(alignment: .topTrailing) {
                badgeView(for: item.badge, iconSize: settings.iconSize)
                  .offset(x: settings.iconSize * 0.1, y: -settings.iconSize * 0.05)
              }
            } else {
              iconImage
            }
            if settings.showNames {
              Text(item.appName)
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .lineLimit(1)
            }
          }
        }
      }
      .padding(.horizontal, settings.padding)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(Color(nsColor: settings.tint.nsColor).opacity(0.15))
          )
      }
      .opacity(settings.opacity)
    }
  }

  @ViewBuilder
  private func badgeView(for badge: Badge, iconSize: Double) -> some View {
    let badgeSize = max(iconSize * 0.44, 16.0)

    Circle()
      .fill(.red)
      .frame(width: badgeSize, height: badgeSize)
      .overlay {
        if badge.kind == .count {
          Text(badge.raw)
            .font(.system(size: badgeSize * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        }
      }
  }
}
