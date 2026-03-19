APP_NAME   = ActionItems
BUNDLE_ID  = com.hari.actionitems
APP_PATH   = $(shell pwd)/$(APP_NAME).app
DEBUG_BIN  = $(shell pwd)/.build/debug/$(APP_NAME)
RELEASE_BIN = $(shell pwd)/.build/release/$(APP_NAME)
ENTITLEMENTS = $(shell pwd)/$(APP_NAME).entitlements
INFO_PLIST = $(shell pwd)/Info.plist
SIGN_IDENTITY = ActionItems Dev

.PHONY: build release bundle sign run dmg clean kill rebuild

# ── Development ──────────────────────────────────────────────────────────────

## Build (debug)
build:
	swift build

## Create .app bundle from binary
bundle:
	@echo "→ Creating .app bundle..."
	@mkdir -p "$(APP_PATH)/Contents/MacOS"
	@mkdir -p "$(APP_PATH)/Contents/Resources"
	@if [ -f "$(RELEASE_BIN)" ] && [ "$(RELEASE_BIN)" -nt "$(DEBUG_BIN)" ]; then \
		cp "$(RELEASE_BIN)" "$(APP_PATH)/Contents/MacOS/$(APP_NAME)"; \
		echo "→ Using release binary"; \
	else \
		swift build 2>&1 | tail -3; \
		cp "$(DEBUG_BIN)" "$(APP_PATH)/Contents/MacOS/$(APP_NAME)"; \
		echo "→ Using debug binary"; \
	fi
	@cp "$(INFO_PLIST)" "$(APP_PATH)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(APP_PATH)/Contents/Resources/AppIcon.icns"; fi
	@echo "→ Bundle ready"

## Sign the bundle
sign: bundle
	@echo "→ Signing..."
	@codesign --force --deep --sign "$(SIGN_IDENTITY)" \
		--entitlements "$(ENTITLEMENTS)" "$(APP_PATH)"
	@echo "→ Signed OK"

## Kill running instance
kill:
	@pkill -x $(APP_NAME) 2>/dev/null || true

## Build + sign + launch (dev)
run: kill sign
	@open "$(APP_PATH)"
	@echo "→ Running — look for the icon in your menu bar"

## Full clean
rebuild: clean run

# ── Distribution ─────────────────────────────────────────────────────────────

## Build optimised release binary
release:
	@echo "→ Building release..."
	@swift build -c release
	@echo "→ Release binary ready"

## Create installable DMG (drag-to-Applications)
DMG_PATH    = $(shell pwd)/ActionItems.dmg
DMG_STAGING = /tmp/ActionItems_dmg_staging

dmg: release sign
	@echo "→ Creating DMG..."
	@rm -rf "$(DMG_STAGING)" && mkdir -p "$(DMG_STAGING)"
	@cp -r "$(APP_PATH)" "$(DMG_STAGING)/"
	@ln -s /Applications "$(DMG_STAGING)/Applications"
	@rm -f "$(DMG_PATH)"
	@hdiutil create \
		-volname "ActionItems" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO \
		"$(DMG_PATH)" > /dev/null
	@rm -rf "$(DMG_STAGING)"
	@echo "→ DMG ready: $(DMG_PATH)"
	@open -R "$(DMG_PATH)"

clean: kill
	@rm -rf .build "$(APP_PATH)" "$(DMG_PATH)"
	@echo "→ Cleaned"
