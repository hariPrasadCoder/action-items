APP_NAME     = ActionItems# SPM target name (binary name)
DISPLAY_NAME = Flaxie               # shown in Finder / menu bar
BUNDLE_ID    = com.hari.actionitems
APP_PATH     = $(shell pwd)/Flaxie.app
DEBUG_BIN    = $(shell pwd)/.build/debug/$(APP_NAME)
RELEASE_BIN  = $(shell pwd)/.build/release/$(APP_NAME)
ENTITLEMENTS = $(shell pwd)/ActionItems.entitlements
INFO_PLIST   = $(shell pwd)/Info.plist
SIGN_IDENTITY = -   # ad-hoc signing; replace with "Apple Development: you@email.com" if you have a cert

.PHONY: build release bundle sign run dmg clean kill rebuild xcode

# ── Development ───────────────────────────────────────────────────────────────

## Build debug binary
build:
	swift build

## Open in Xcode (Package.swift as Xcode workspace)
xcode:
	xed .

## Create .app bundle from binary
bundle:
	@echo "→ Creating Flaxie.app bundle..."
	@mkdir -p "$(APP_PATH)/Contents/MacOS"
	@mkdir -p "$(APP_PATH)/Contents/Resources"
	@if [ -f "$(RELEASE_BIN)" ] && [ "$(RELEASE_BIN)" -nt "$(DEBUG_BIN)" ]; then \
		swift build -c release 2>&1 | tail -2; \
		cp "$(RELEASE_BIN)" "$(APP_PATH)/Contents/MacOS/$(APP_NAME)"; \
		echo "→ Using release binary"; \
	else \
		swift build 2>&1 | tail -2; \
		cp "$(DEBUG_BIN)" "$(APP_PATH)/Contents/MacOS/$(APP_NAME)"; \
		echo "→ Using debug binary"; \
	fi
	@cp "$(INFO_PLIST)" "$(APP_PATH)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns "$(APP_PATH)/Contents/Resources/AppIcon.icns"; \
	fi
	@echo "→ Bundle ready at $(APP_PATH)"

## Sign the bundle (ad-hoc by default)
sign: bundle
	@echo "→ Signing with: $(SIGN_IDENTITY)"
	@codesign --force --deep --sign "$(SIGN_IDENTITY)" \
		--entitlements "$(ENTITLEMENTS)" \
		--options runtime \
		"$(APP_PATH)"
	@echo "→ Signed OK"

## Kill any running instance
kill:
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@pkill -f "Flaxie.app" 2>/dev/null || true

## Build + sign + launch (quickest dev loop)
run: kill sign
	@open "$(APP_PATH)"
	@echo "→ Flaxie running — look for the sparkles icon in your menu bar"

## Full rebuild from scratch
rebuild: clean run

# ── Distribution ──────────────────────────────────────────────────────────────

## Build optimised release binary
release:
	@echo "→ Building release..."
	@swift build -c release
	@echo "→ Release binary ready"

## Create installable DMG
DMG_PATH    = $(shell pwd)/Flaxie.dmg
DMG_STAGING = /tmp/Flaxie_dmg_staging

dmg: release sign
	@echo "→ Creating DMG..."
	@rm -rf "$(DMG_STAGING)" && mkdir -p "$(DMG_STAGING)"
	@cp -r "$(APP_PATH)" "$(DMG_STAGING)/"
	@ln -s /Applications "$(DMG_STAGING)/Applications"
	@rm -f "$(DMG_PATH)"
	@hdiutil create \
		-volname "Flaxie" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO \
		"$(DMG_PATH)" > /dev/null
	@rm -rf "$(DMG_STAGING)"
	@echo "→ DMG ready: $(DMG_PATH)"
	@open -R "$(DMG_PATH)"

clean: kill
	@rm -rf .build "$(APP_PATH)" "$(DMG_PATH)"
	@echo "→ Cleaned"
