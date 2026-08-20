APP_NAME := Ping
APP := $(APP_NAME).app
# `ping` is /sbin/ping, so the CLI ships under a name macOS has not taken. See Package.swift.
CLI_NAME := ping-dot-app
DIST := dist
CONFIG := release
SWIFT_BUILD := swift build -c $(CONFIG)
INSTALL_DIR ?= /Applications

.DEFAULT_GOAL := app
.PHONY: app build cli icon install test format lint run zip dist clean print-version

# The git tag is the only version authority (IMPLEMENTATION.md §14); outside a checkout, 0.0.0.
GIT_DESCRIBE := $(shell git describe --tags --match 'v[0-9]*' --dirty 2>/dev/null)
VERSION      ?= $(if $(GIT_DESCRIBE),$(patsubst v%,%,$(GIT_DESCRIBE)),0.0.0)
BUILD        ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 0)

print-version:
	@echo $(VERSION)

# Ad-hoc signing runs locally but re-asks for Accessibility on every build; a Developer ID in
# CODESIGN_IDENTITY holds the grant, and brings the two flags notarization requires with it
# (IMPLEMENTATION.md §14).
CODESIGN_IDENTITY ?= -
ifeq ($(CODESIGN_IDENTITY),-)
  SIGN_FLAGS :=
else
  SIGN_FLAGS := --options runtime --timestamp
endif

# `actool` lives in Xcode, not the Command Line Tools, so a machine without it gets a bundle with no
# icon rather than a failed build (IMPLEMENTATION.md §14). `xcrun --find` is the probe:
# /usr/bin/actool exists either way and only errors when asked to do something.
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
	@# Both extra outputs are actool's insistence, not ours: the partial plist restates what
	@# Info.plist already says and stays in $(DIST), and .icns is read only by a macOS older than
	@# this bundle's floor.
	@rm -f "$(APP)/Contents/Resources/$(APP_NAME).icns"
endif

app: build
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@bin_dir="$$($(SWIFT_BUILD) --show-bin-path)"; \
	cp "$$bin_dir/PingApp" "$(APP)/Contents/MacOS/Ping"; \
	cp "$$bin_dir/$(CLI_NAME)" "$(APP)/Contents/MacOS/$(CLI_NAME)"; \
	cp -a "$$bin_dir/Ping_PingUI.bundle" "$(APP)/Contents/Resources/"
	@cp -a ".app/" "$(APP)/"
	@# cp -a carries extended attributes across, so a quarantine flag on any of the template's
	@# files would be inherited by the bundle and get it killed on launch.
	@xattr -dr com.apple.quarantine "$(APP)" 2>/dev/null || true
	@$(MAKE) --no-print-directory icon
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
	                         -c "Set :CFBundleVersion $(BUILD)" "$(APP)/Contents/Info.plist"
	@# The resource bundle is left unsigned: it carries a font, an SVG and a license and no code,
	@# so the app's own seal already covers it.
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(SIGN_FLAGS) "$(APP)/Contents/MacOS/$(CLI_NAME)"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" $(SIGN_FLAGS) "$(APP)"
	@echo "Built $(APP) — version $(VERSION) ($(BUILD))"

build:
	@echo "Building Ping ($(CONFIG))..."
	$(SWIFT_BUILD)
	@# SwiftPM's generated accessor looks for the resource bundle beside Bundle.main.bundleURL —
	@# the .app root, where codesigning will not have it. Point it at resourceURL instead and
	@# rebuild. Newer toolchains already prefer resourceURL, so this is a no-op there.
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

# The unbundled CLI's path — the better symlink target while working on it, since it tracks
# `make build` rather than the last bundle.
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

install: app
	@rm -rf "$(INSTALL_DIR)/$(APP)"
	@ditto "$(APP)" "$(INSTALL_DIR)/$(APP)"
	@echo "Installed $(INSTALL_DIR)/$(APP) — quit and relaunch Ping to pick it up"

# `zip` does not depend on `app`: notarization runs between the two, and re-signing would discard
# the stapled ticket. `make dist` is the ordinary path.
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
