// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Target graph (IMPLEMENTATION.md §3):
//
//   PingConfig  — no AppKit, no UI: grammar · schema · document · diagnostics
//        ▲
//   PingCore    — AppKit for AX only: dock reading · badge state · resolution
//        ▲
//   PingUI      — SwiftUI/AppKit: windows · renderers · settings · resources
//        ▲
//   PingApp (@main)  ·  ping-dot-app (CLI)
//
// Neither executable product is named for what it becomes. The app's is `PingApp`, which
// the Makefile copies into the bundle as Contents/MacOS/Ping — what CFBundleExecutable
// names. Naming the product `Ping` outright would not survive a case-insensitive
// filesystem, which is the default: `Ping` and `ping` land on the same path in the bin
// directory and silently clobber each other.
//
// The CLI's is `ping-dot-app`, because `ping` is /sbin/ping. A binary shipped onto a
// user's PATH has to be a name macOS has not already taken, and shadowing the one command
// every person on the machine expects to reach ICMP is not a trade worth making. The name
// it prints in its own usage comes from argv[0], so a symlink under any other name still
// describes itself correctly.
let package = Package(
  name: "Ping",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(name: "PingApp", targets: ["PingApp"]),
    .executable(name: "ping-dot-app", targets: ["PingCLI"]),
  ],
  targets: [
    .target(name: "PingConfig"),
    .target(name: "PingCore", dependencies: ["PingConfig"]),
    .target(
      name: "PingUI",
      dependencies: ["PingConfig", "PingCore"],
      resources: [
        .process("Resources/Chango-Regular.ttf"),
        // The OFL requires Chango's copyright notice and license to travel with the font in
        // every copy, so it ships inside the resource bundle rather than sitting in the repo.
        .copy("Resources/OFL.txt"),
        .copy("Resources/Bell.svg"),
      ]),
    .executableTarget(
      name: "PingCLI",
      dependencies: ["PingConfig"],
      path: "Sources/PingCLI"),
    .executableTarget(
      name: "PingApp",
      dependencies: ["PingConfig", "PingCore", "PingUI"],
      path: "Sources/Ping"),
    .testTarget(name: "PingConfigTests", dependencies: ["PingConfig"]),
    .testTarget(name: "PingCoreTests", dependencies: ["PingCore"]),
    .testTarget(name: "PingUITests", dependencies: ["PingUI"]),
  ]
)
