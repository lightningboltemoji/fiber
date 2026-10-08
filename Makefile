# Fiber's entry points: the Chromium checkout and dev build (scripts/ does the work), the UI on its
# own, and the app bundle for /Applications. See .agents/IMPLEMENTATION.md for how it all fits.

APP_NAME := $(shell sed -n 's/^PRODUCT_FULLNAME=//p' core/branding/BRANDING)
OUT      ?= Default
SRC      := chromium/src

.PHONY: sync patches build run size ui harness icon app zip dist install uninstall clean print-version \
        demo demo-take demo-render demo-studio

# --- Chromium and the dev build ------------------------------------------------------------------
# `build` is the component build in out/$(OUT): hundreds of small dylibs, so an incremental build
# relinks in seconds. Its Fiber.app loads them from out/$(OUT) and only runs from there.
# Rebases the patches onto a new CHROMIUM_VERSION (scripts/rebase_patches.sh).
sync:
	scripts/sync_chromium.sh

# Regenerates patches/chromium/ from your edits in chromium/src.
patches:
	scripts/update_patches.sh

build:
	scripts/build_chromium.sh $(OUT)

# Against the dev profile in chromium/dev-profile. `make run URL=…` opens a page.
run:
	OUT=$(OUT) scripts/run.sh $(URL)

# What Chrome's layer costs, by source directory, and how much the linker strips (scripts/size.py).
# Run it before and after a change and it reports what moved. `make size PATHS=…` adds directories.
size:
	scripts/size.py --out $(OUT) $(PATHS)

# --- The UI on its own ---------------------------------------------------------------------------
# SwiftPM builds core/ui without Chromium; if it builds here, FiberUI doesn't depend on Chromium.
ui:
	swift build --package-path core/ui

harness:
	swift run --package-path core/ui FiberUIHarness

# --- The app icon --------------------------------------------------------------------------------
# Regenerates the icon's sources in core/branding/icon, and core/ui's FiberMark.swift. The build
# compiles the icon into the app (//fiber/branding:app_icon). uv installs the generator's
# dependencies from its inline script metadata.
icon:
	uv run core/branding/icon/build.py

# --- The demo video ------------------------------------------------------------------------------
# The director plays demo/tapes/$(TAPE).tape on out/Release's app (APP=… for another) and records
# the take into demo/takes/$(TAPE); the studio cuts takes into demo/studio/out/$(CUT).mp4. A take
# takes over the mouse and keyboard while it records. See .agents/DEMO.md.
TAPE     ?= readme
CUT      ?= $(TAPE)
DIRECTOR := demo/director/.build/release/director

demo: demo-take demo-render

demo-take:
	swift build -c release --package-path demo/director
	$(DIRECTOR) demo/tapes/$(TAPE).tape $(if $(APP),--app $(APP))

demo-render:
	cd demo/studio && npm ci --silent && \
		npx remotion render src/index.ts $(CUT) out/$(CUT).mp4 $(if $(CRF),--crf=$(CRF))

# Previews and scrubs the cuts in a browser, to tune the camera.
demo-studio:
	cd demo/studio && npm ci --silent && npx remotion studio src/index.ts

# --- Version -------------------------------------------------------------------------------------
# Fiber's version is core/branding/VERSION; tag its release v<VERSION>. The app shows it with the
# Chromium release it's built on, 0.1.0c155.8059.12 (core/branding/version.gni), and archives are
# named for that, read from the bundle. A build that isn't the release's tag adds its commit.
FIBER_VERSION  := $(shell cat core/branding/VERSION)
RELEASE_TAG    := $(shell git describe --tags --match 'v$(FIBER_VERSION)' --dirty 2>/dev/null)
COMMIT         := $(shell git describe --always --dirty --exclude '*' 2>/dev/null)
VERSION_SUFFIX := $(if $(filter v$(FIBER_VERSION),$(RELEASE_TAG)),,-$(COMMIT))
BUNDLE_VERSION  = /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
                  $(BUNDLE)/Contents/Info.plist

print-version:
	@echo $(FIBER_VERSION)

# --- Fiber.app -----------------------------------------------------------------------------------
# The dev build's app can't leave out/$(OUT), so the bundle comes from out/Release: one framework,
# so the app runs anywhere, with DCHECKs off (scripts/build_chromium.sh). Its first build compiles
# all of Chromium again (hours); after that, every change relinks the whole framework.
DIST     := dist
BUNDLE   := $(DIST)/$(APP_NAME).app
RELEASE  := $(SRC)/out/Release

# Chromium's build assembles the bundle; `ditto` copies it with the framework's symlinks intact.
# Signed ad hoc as a whole: with only the linker's signatures (no bundle ID), macOS's Local Network
# privacy blocks the app from the local network even after the user allows it.
# TODO: sign for distribution (Developer ID, chrome/installer/mac/sign_chrome.py).
app:
	scripts/build_chromium.sh Release
	rm -rf $(BUNDLE)
	mkdir -p $(DIST)
	ditto $(RELEASE)/$(APP_NAME).app $(BUNDLE)
	codesign --force --deep --sign - $(BUNDLE)
	@echo "built $(BUNDLE), version $$($(BUNDLE_VERSION))"

# `ditto`, not `zip`: a bundle carries symlinks and xattrs that plain zip mangles. CI's tip build
# sets ZIP_NAME, for an archive whose URL doesn't change.
ZIP_NAME ?= $(APP_NAME)-$$($(BUNDLE_VERSION))$(VERSION_SUFFIX).zip

zip:
	@zip="$(DIST)/$(ZIP_NAME)" && \
	rm -f "$$zip" && \
	ditto -c -k --keepParent $(BUNDLE) "$$zip" && \
	shasum -a 256 "$$zip"

dist: app zip

# Refuses while the installed copy is running, since it loads files from the bundle it's replacing.
# The installed app keeps its profile in ~/Library/Application Support/$(APP_NAME), separate from
# the dev profile.
INSTALLED := /Applications/$(APP_NAME).app

install: app
	@if pgrep -qf "^$(INSTALLED)/Contents/MacOS/"; then \
		echo "$(APP_NAME) is running from /Applications; quit it first" >&2; exit 1; fi
	rm -rf $(INSTALLED)
	ditto $(BUNDLE) $(INSTALLED)
	@echo "installed $(INSTALLED)"

uninstall:
	rm -rf $(INSTALLED)

# Leaves chromium/src/out alone: rebuilding it takes hours. Delete an out dir by hand if needed.
clean:
	rm -rf $(DIST) core/ui/.build
