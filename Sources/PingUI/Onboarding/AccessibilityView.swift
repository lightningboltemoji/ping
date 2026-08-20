//
//  AccessibilityView.swift
//  PingUI
//
//  Created by Tanner on 10/3/25.
//

@preconcurrency import ApplicationServices
internal import Combine
import SwiftUI
import os

private let logger = Logger(subsystem: "Ping", category: "accessibility")

public struct AccessibilityView: View {

  @State private var hasPermission = AXIsProcessTrusted()
  @Environment(\.dismiss) private var dismiss

  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  public init() {}

  public var body: some View {
    VStack {
      if !hasPermission {
        VStack {
          VStack(spacing: 24) {
            // Header
            VStack(spacing: 4) {
              Text("ping").font(.custom("Chango", size: 48))
              Text("Never miss a notification")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }

          Text(
            "Accessbility permissions are required"
          ).fontWeight(.bold).padding(.top, 10)

          Text(
            "The Accessibility API is used to communicate with Dock.app to check what apps have notification badges"
          ).multilineTextAlignment(.center).padding(.horizontal, 20)
            .padding(.top, 10)

          Button("Open Accessibility Settings") {
            Task {
              AccessibilityView.openSettings()
            }
          }.padding(.top, 15)

          Text(
            "Unfortunately, I don't think there's an alternative :("
          ).multilineTextAlignment(.center).padding(.horizontal, 20)
            .padding(.top, 15).font(
              .system(size: 11, weight: .thin)
            )
        }
        .frame(width: 400)
        .padding()
        .fixedSize()
        .onAppear {
          AccessibilityView.requestAxPermission()
        }
      } else {
        EmptyView().frame(width: 0, height: 0).hidden()
      }
    }
    .onReceive(timer) { _ in
      hasPermission = AXIsProcessTrusted()
      if hasPermission {
        dismiss()
      }
    }
  }

  private static func hasAxPermission() -> Bool {
    return AXIsProcessTrusted()
  }

  private static func requestAxPermission() {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ]
    logger.info("AXIsProcessTrusted: \(AXIsProcessTrustedWithOptions(options as CFDictionary))")
  }

  private static func openSettings() {
    if let url = URL(
      string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ) {
      NSWorkspace.shared.open(url)
    }
  }
}
