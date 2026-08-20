APP_NAME := Ping
APP := $(APP_NAME).app
# `ping` is /sbin/ping, so the CLI ships under a name macOS has not taken. See Package.swift.
CLI_NAME := ping-dot-app
DIST := dist
CONFIG := release
SWIFT_BUILD := swift build -c $(CONFIG)

.DEFAULT_GOAL := app
.PHONY: app build cli icon test format lint run zip dist clean print-version

# --- Version -------------------------------------------------------------------------------------
# The git tag is the only version authority; nothing in the tree carries a number. A tagged commit
# builds `0.2.0`, anything else builds what `git describe` says, and outside a checkout `0.0.0`.
# `app` stamps both keys into the bundle's *copy* of Info.plist, never into `.app/`'s source copy.
GIT_DESCRIBE := $(shell git describe --tags --match 'v[0-9]*' --dirty 2>/dev/null)
VERSION      ?= $(if $(GIT_DESCRIBE),$(patsubst v%,%,$(GIT_DESCRIBE)),0.0.0)
BUILD        ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 0)

print-version:
	@echo $(VERSION)

# --- Signing -------------------------------------------------------------------------------------
# Ad-hoc (`--sign -`) is enough to load and run locally. It is *not* enough for TCC to remember the
# Accessibility grant across rebuilds: an ad-hoc signature is identified by its cdhash, which changes
# with every build, so macOS treats each build as a new app and re-asks. `CODESIGN_IDENTITY`
# overrides it with a Developer ID, which brings the hardened runtime and a secure timestamp with it
# — both of which notarization requires.
#
# The nested CLI is signed *before* the app: signing a bundle seals its `Contents` into
# `CodeResources`, so nested *code* signed afterwards would invalidate the outer signature.
#
# The resource bundle is deliberately *not* signed. It holds a font, an SVG and a license and no
# code, so the outer seal already covers it: its files appear in the app's own `CodeResources`
# either way, and `codesign --verify --deep --strict` passes with the nested bundle unsigned.
CODESIGN_IDENTITY ?= -
ifeq ($(CODESIGN_IDENTITY),-)
  SIGN_FLAGS :=
else
  SIGN_FLAGS := --options runtime --timestamp
endif

# --- The app icon --------------------------------------------------------------------------------
# `Icon/Ping.icon` is the source: the pixel bell as an SVG layer plus the `icon.json` that composes
# it over a gradient. Composing it that way rather than shipping a flat image is what buys the
# macOS 26 appearances — the system draws the squircle, the glass and the specular highlight itself,
# and re-renders the fill for the dark, tinted and clear variants from the same two files.
#
# The bell is black, which is the one thing in here that is a *choice* rather than a default, and it
# costs something. macOS builds the tinted and clear appearances out of the layer's luminance, so a
# dark glyph comes back as a faint emboss where a white one would stay solid; the trade was made
# deliberately, for a 17:1 bell against the green in the appearance most people see. It also forces
# the `dark` fill in `icon.json` to be stated rather than left out: with no dark fill the system
# darkens the ground automatically, which would put a black bell on a near-black square. If the bell
# ever turns white, that dark fill can go back to being automatic.
#
# macOS does not read that directory: `actool` compiles it into an `Assets.car`, and
# `CFBundleIconName` names the icon inside. **`actool` lives in Xcode, not the Command Line Tools**,
# so a CLT-only machine cannot compile the icon at all. That is not worth failing a build over — a
# bundle without an icon runs exactly as well — so this compiles the icon when it can and says so
# when it cannot. `xcrun --find` is the probe: `/usr/bin/actool` exists either way and only errors
# when asked to do something.
#
# actool insists on writing a partial Info.plist naming the icon, which `.app/Contents/Info.plist`
# already states; it goes to $(DIST) and is never copied in. It also always writes a legacy
# `Ping.icns`, and that one is deleted: `.icns` is what a macOS older than 26 would read, which
# `LSMinimumSystemVersion` rules out.
ICON   := Icon/$(APP_NAME).icon
ACTOOL := $(shell xcrun --find actool 2>/dev/null)

icon:
ifeq ($(ACTOOL),)
	@echo "warning: no actool — needs Xcode, not Command Line Tools. Bundle gets no icon."
else
	@mkdir -p "$(DIST)"
	@$(ACTOOL) "$(ICON)" --compile "$(APP)/Contents/Resources" \
		--app-icon $(APP_NAME) --include-all-app-icons \
		--platform macosx --target-device mac \
		--minimum-deployment-target 26.0 --development-region en \
		--output-partial-info-plist "$(DIST)/icon-partial.plist" \
		--output-format human-readable-text --notices --warnings --errors
	@rm -f "$(APP)/Contents/Resources/$(APP_NAME).icns"
endif

# Assemble the built binaries and resources into a signed .app bundle.
#
# **Both executables go in the bundle.** `Ping` is `CFBundleExecutable`; the CLI rides along at
# `Contents/MacOS/$(CLI_NAME)` so there is exactly one copy of the config reader on the machine and
# no chance of a CLI and an app from different builds disagreeing about what the file means. Nothing
# here puts it on `$$PATH` — that is the Homebrew cask's `binary` stanza, or a symlink you make.
app: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@bin_dir="$$($(SWIFT_BUILD) --show-bin-path)"; \
	cp "$$bin_dir/PingApp" "$(APP)/Contents/MacOS/Ping"; \
	cp "$$bin_dir/$(CLI_NAME)" "$(APP)/Contents/MacOS/$(CLI_NAME)"; \
	cp -a "$$bin_dir/Ping_PingUI.bundle" "$(APP)/Contents/Resources/"
	@cp -a ".app/" "$(APP)/"
	@# cp -a carries extended attributes across, so a quarantine flag on any of the
	@# template's files would be inherited by the bundle and get it killed on launch.
	@xattr -dr com.apple.quarantine "$(APP)" 2>/dev/null || true
	@$(MAKE) --no-print-directory icon
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
	                         -c "Set :CFBundleVersion $(BUILD)" "$(APP)/Contents/Info.plist"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(SIGN_FLAGS) "$(APP)/Contents/MacOS/$(CLI_NAME)"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(SIGN_FLAGS) "$(APP)"
	@echo "Built $(APP) — version $(VERSION) ($(BUILD))"

build:
	@echo "Building Ping ($(CONFIG))..."
	$(SWIFT_BUILD)
	@# SwiftPM's generated accessor used to look for the resource bundle via
	@# Bundle.main.bundleURL (the .app root), but codesigning requires everything to
	@# be inside Contents/. Patch the accessor to use resourceURL (Contents/Resources/)
	@# and rebuild incrementally so the binary looks in the right place. Newer
	@# toolchains already prefer resourceURL, so this is a no-op there.
	@patched=0; \
	for accessor in $$(find .build -name resource_bundle_accessor.swift); do \
		if ! grep -q 'Bundle\.main\.resourceURL' "$$accessor"; then \
			sed -i '' 's/Bundle\.main\.bundleURL/(Bundle.main.resourceURL ?? Bundle.main.bundleURL)/' "$$accessor"; \
			patched=1; \
		fi; \
	done; \
	if [ "$$patched" = 1 ]; then \
		echo "Patched resource bundle accessor, rebuilding..."; \
		$(SWIFT_BUILD); \
	fi

# Where `swift build` left the CLI, for symlinking onto PATH. The bundled copy at
# `$(APP)/Contents/MacOS/$(CLI_NAME)` is the one a release installs; this is the one a
# `make build` tree has, and it is the better symlink target while you are working on it.
cli: build
	@echo "$$($(SWIFT_BUILD) --show-bin-path)/$(CLI_NAME)"

test:
	swift test

format:
	swift format -irp .

# What `format` would change, as a failure rather than an edit — for CI.
lint:
	swift format lint -rsp .

run: app
	open "$(APP)"

# --- The release archive -------------------------------------------------------------------------
# `ditto`, not `zip`: a bundle carries symlinks, xattrs and a signature that plain zip mangles, and
# it is the format `notarytool` takes. `zip` does not depend on `app` because notarization runs
# between them and a re-sign would discard the stapled ticket — `make dist` is the ordinary path.
ZIP_NAME ?= $(APP_NAME)-$(VERSION).zip
ZIP      := $(DIST)/$(ZIP_NAME)

zip:
	@mkdir -p "$(DIST)"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	@shasum -a 256 "$(ZIP)"

dist: app zip

clean:
	swift package clean
	rm -rf "$(APP)" "$(DIST)"
