# Fiber's entry points: the Chromium checkout and dev build (scripts/ does the work), the UI on its
# own, and the app bundle for /Applications. See .agents/IMPLEMENTATION.md for how it all fits.

APP_NAME := $(shell sed -n 's/^PRODUCT_FULLNAME=//p' core/branding/BRANDING)
OUT      ?= Default
SRC      := chromium/src

.PHONY: sync patches build run size ui harness icon app zip dist install uninstall clean print-version

# --- Chromium and the dev build ------------------------------------------------------------------
# `build` is the component build in out/$(OUT): hundreds of small dylibs, so an incremental build
# relinks in seconds. Its Fiber.app loads them from out/$(OUT) and only runs from there.
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
# Regenerates core/branding/icon/AppIcon.icon and its renders. The build compiles the icon into the app
# (//fiber/branding:app_icon); this only regenerates the source. uv installs the generator's
# dependencies from its inline script metadata.
icon:
	uv run core/branding/icon/build.py

# --- Version -------------------------------------------------------------------------------------
# The bundle carries Chromium's version (CHROMIUM_VERSION); Fiber has none of its own yet. Archives
# are named for the Fiber commit: its v* tag if it has one, otherwise the short hash.
GIT_DESCRIBE := $(shell git describe --tags --match 'v[0-9]*' --always --dirty 2>/dev/null)
VERSION      ?= $(if $(GIT_DESCRIBE),$(patsubst v%,%,$(GIT_DESCRIBE)),0.0.0)

print-version:
	@echo $(VERSION)

# --- Fiber.app -----------------------------------------------------------------------------------
# The dev build's app can't leave out/$(OUT), so the bundle comes from its own build in out/Release:
# not a component build (everything in the one framework, so the app runs from anywhere) and without
# DCHECKs, which are fatal (see scripts/build_chromium.sh). The first build of out/Release compiles
# all of Chromium again, which takes hours; after that it's incremental, but every change relinks
# the whole framework.
#
# Chromium's build already assembles the bundle, so this only copies it. `ditto` keeps the
# framework's symlinks intact. The binaries carry the linker's ad-hoc signatures, which is enough to
# run locally. Signing for distribution needs a Developer ID and Chromium's own signer
# (chrome/installer/mac/sign_chrome.py, which sets up the hardened runtime and entitlements); it
# isn't wired up yet.
DIST     := dist
BUNDLE   := $(DIST)/$(APP_NAME).app
RELEASE  := $(SRC)/out/Release

app:
	scripts/build_chromium.sh Release
	rm -rf $(BUNDLE)
	mkdir -p $(DIST)
	ditto $(RELEASE)/$(APP_NAME).app $(BUNDLE)
	@echo "built $(BUNDLE) — Chromium $$(cat CHROMIUM_VERSION), Fiber $(VERSION)"

# `ditto`, not `zip`: a bundle carries symlinks and xattrs that plain zip mangles.
ZIP := $(DIST)/$(APP_NAME)-$(VERSION).zip

zip:
	rm -f $(ZIP)
	ditto -c -k --keepParent $(BUNDLE) $(ZIP)
	@shasum -a 256 $(ZIP)

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
