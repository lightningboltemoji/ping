# Ping.app <img width="24" alt="Bell icon" src="/Sources/PingUI/Resources/Bell.svg"/>

Ping works by reading what items in your dock **have a red badge** and **adds screen overlays** to make sure they don't get missed.

For example, with the Messages app set to glow green, and the Mail app set to glow blue:

<img width="600" alt="Video of the plugin clearing an unsent message from the chatbox" src="/.github/preview.webp"/>

## Config

Ping uses `~/.config/ping/ping.toml` to store all app-specific visualization rules.

```toml
suppress-when-focused = true    # no effect for the app you're looking at

[glow]
edge  = "bottom"                # "top" | "bottom" | "left" | "right"
color = "green"                 # a name, or "#rrggbb" / "#rrggbbaa"

[apps.Slack]
glow  = { color = "#611f69", edge = "left" }
shelf = {}                      # and put it on the shelf
notch = { color = "#611f69" }   # and a dot in the notch

[apps.Messages.glow]
color = "green"

[apps.Messages.glow.dot]
enabled = false                 # only glow when there's an actual count

[apps.Messages.notch.dot]
color = "white"                 # a bare dot is quieter than a count
```

The CLI utility (`ping-dot-app`) can be used to both validate and explain:

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

Settings can also be changed via GUI using `Settings` in the menu bar.

## Watch

Ping's reading of the Dock is available to anything else that wants to show it, like a status bar or a
script. `watch` prints it as JSON, one line per change, starting with the current one:

```
$ ping-dot-app watch
{"apps":[{"acknowledged":false,"badge":"3","count":3,"name":"Slack","path":"/Applications/Slack.app"}, …],"snoozed":false,"version":1}
```

Every app in the Dock is listed, badged or not. `badge` is exactly what the Dock shows (`null` for none,
`""` for a bare dot), `count` is set when that is a number, and `acknowledged` and `snoozed` are what
you told Ping from the menu bar. `watch` exits 69 when Ping isn't running.

## Install

[Homebrew](https://brew.sh) is recommended:

```bash
brew install --cask lightningboltemoji/tap/ping
```

or manually from the [releases page](https://github.com/lightningboltemoji/Ping/releases).

## Building

To build and package into Ping.app:

```
make
```

## Motivation

macOS' notification system doesn't work very well for me. With apps like Slack, I sometimes miss notifications because:

1. It's not visually intrusive enough (e.g. light notification against light browser window)
2. It's not persistent, so I'll notice it initially but forget to revisit

Previously, I used [SketchyBar](https://github.com/FelixKratz/SketchyBar) to put Slack notifications in my menu bar. This is a great setup, but moving away from the default menu bar causes other inconveniences for my workflow, so I wanted a solution that wasn't so drastic.

## License

Ping is [GPL-3.0](LICENSE.md).

[Chango](https://fonts.google.com/specimen/Chango) typeface — © 2011 Fontstage, under the [SIL Open Font License 1.1][ofl].

[ofl]: Sources/PingUI/Resources/OFL.txt
