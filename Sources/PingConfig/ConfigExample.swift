//
//  ConfigExample.swift
//  PingConfig
//
//  A worked example of every section, pinned by a test that parses it. Generating it from the
//  enumerable settings table is the eventual answer; for now this is written by hand and the test
//  is what keeps it honest.
//

public enum ConfigExample {
  public static let text = """
    # ~/.config/ping/ping.toml

    # ─── General ──────────────────────────────────────────────────────────
    poll-interval-ms      = 500     # how often the Dock is read (100–2000)
    monitors              = "main"  # "main" | "all"
    suppress-when-focused = true    # no effect for the app you're looking at
    launch-at-login       = false

    # ─── Glow — a gradient bleeding in from a screen edge ─────────────────
    [glow]
    enabled = true                  # master switch for the whole effect
    edge    = "bottom"              # "top" | "bottom" | "left" | "right"
    color   = "green"               # a name, or "#rrggbb" / "#rrggbbaa"
    size    = 1.0                   # 0.25–1.0, how far the gradient reaches
    opacity = 1.0                   # 0.0–1.0

    [glow.pulse]                    # the breathing animation
    duration-ms  = 2000
    min-opacity  = 0.25
    max-opacity  = 0.95
    crossfade-ms = 400              # when several apps share one edge

    # ─── Shelf — a small overlay bar of badged app icons ──────────────────
    [shelf]
    enabled     = true
    anchor      = "top-center"      # {top,bottom}-{left,center,right}
    margin      = 20                # px from the screen edge
    padding     = 16                # px inside the bar
    icon-size   = 32
    opacity     = 0.8
    tint        = "white"
    show-names  = true
    show-badges = true

    # ─── Notch — indicators in a strip that grows out of the notch ────────
    [notch]
    enabled       = true            # master switch for the whole effect
    placement     = "split"         # "left" | "right" | "split"
    style         = "dot"           # "dot" | "icon" | "count"
    max-width     = 120             # extra px per side; past this the tail takes turns
    always-show   = false           # a stand-in notch on a screen without one
    width         = 185             # that stand-in's own width
    corner-radius = 10
    item-size     = 8               # dot diameter, or icon edge
    gap           = 8               # between one indicator and the next
    grow-ms       = 350             # how long the strip takes to open or close

    # ─── Apps ─────────────────────────────────────────────────────────────
    # The table key is the app's name as it appears in the macOS Dock. An
    # effect applies to an app when it is written under that app; `{}` takes
    # every default.

    [apps.Slack]
    glow  = { color = "#611f69", edge = "left" }
    shelf = {}
    notch = { color = "#611f69" }   # the notch takes `enabled` and `color`, no more

    [apps."Google Chrome"]
    glow = {}

    [apps.Mail]
    glow = { color = "blue", edge = "right", size = 0.6, opacity = 0.7 }

    # Badges come in two kinds: `count` (a number) and `dot` (a bare red
    # dot). Either may override the app's settings, or opt out entirely.
    # Overriding one needs the long form.
    [apps.Messages]
    shelf = {}
    notch = {}                      # red, the Dock badge's own colour

    [apps.Messages.glow]
    color = "green"

    [apps.Messages.glow.dot]
    enabled = false                 # only glow when there's an actual count

    """
}
