# Ping.app <img width="24" alt="Bell icon" src="/Sources/PingUI/Resources/Bell.svg"/>

Ping works by reading what items in your dock **have a red badge** and **adds screen overlays** to make sure they don't get missed.

## Effects

|Effect|Preview|
|--|--|
|**Glow**: pulsing glow on a screen edge, cycling colors for multiple apps|<img width="320" height="180" alt="glow" src="https://github.com/user-attachments/assets/b50b5b1c-9048-4ab1-a315-58e3c39e7ca4" />|
|**Notch**: extends the notch with notification count, dots, or app icons|<img width="320" height="157" alt="notch" src="https://github.com/user-attachments/assets/22ef9bd7-d0f5-4ca9-b544-1aaad1619629" />|
|**Shelf**: a dock-like floating window|<img width="320" height="134" alt="683914044-0e635532-d4bf-4837-bbb0-6d3797e4e1f8" src="https://github.com/user-attachments/assets/ac9c46e3-0644-4a6f-8999-400f22ac03af" />|

## Motivation

macOS' notification system doesn't work very well for me. With apps like Slack, I frequently miss notifications because:

1. It's not visually intrusive enough (e.g. light notification against light browser window)
2. It's not persistent, so I'll notice it initially but forget to revisit

## Install

[Homebrew](https://brew.sh) is recommended:

```bash
brew install --cask lightningboltemoji/tap/ping
```

or manually from the [releases page](https://github.com/lightningboltemoji/Ping/releases).

## Config

Ping uses `~/.config/ping/ping.toml` to store all app-specific visualization rules. The easiest way to create/manage this file is via GUI using `Settings` from the menu bar.

```toml
suppress-when-focused = true    # no effect for the app you're looking at

[glow]
edge  = "bottom"                # "top" | "bottom" | "left" | "right"
color = "green"                 # a name, or "#rrggbb" / "#rrggbbaa"

[apps.Slack]
glow  = { color = "#611f69", edge = "left", dot = { enabled = false } }
shelf = {}                      # and put it on the shelf
notch = { color = "#611f69" }   # and a dot in the notch
```

If you author it manually, the CLI (`ping-dot-app`) can be used to both validate and explain:

```
$ ping-dot-app validate
/Users/you/.config/ping/ping.toml:12: unknown key 'apps.Slack.glow.colour'
```

```
$ ping-dot-app explain glow.size
glow.size
    How far across the screen the gradient reaches.
    must be between 0.25 and 1.0
    default: 1
```

## Watch (advanced)

Ping's reading of the Dock is available to anything else that wants to show it, like a status bar or a
script. `watch` prints it as JSON, one line per change, starting with the current one:

```
$ ping-dot-app watch
{"apps":[{"acknowledged":false,"badge":"3","count":3,"name":"Slack","path":"/Applications/Slack.app"}, …],"snoozed":false,"version":1}
```

Every app in the Dock is listed, badged or not. `badge` is exactly what the Dock shows (`null` for none,
`""` for a bare dot), `count` is set when that is a number, and `acknowledged` and `snoozed` are what
you told Ping from the menu bar. `watch` exits 69 when Ping isn't running.

I use this with [Bario](https://github.com/lightningboltemoji/bario) to [put apps in my system bar](https://github.com/lightningboltemoji/dot/blob/0ec00e584691e4eedcba66f27d3645468ac54d40/bario/config.kdl#L63-L70).

## License

Ping is [GPL-3.0](LICENSE.md).

[Chango](https://fonts.google.com/specimen/Chango) typeface — © 2011 Fontstage, under the [SIL Open Font License 1.1][ofl].

[ofl]: Sources/PingUI/Resources/OFL.txt
