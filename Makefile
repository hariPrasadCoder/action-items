APP_NAME = ActionItems
BUNDLE_ID = com.hari.actionitems
APP_PATH = $(shell pwd)/$(APP_NAME).app
BINARY = $(shell pwd)/.build/debug/$(APP_NAME)
ENTITLEMENTS = $(shell pwd)/$(APP_NAME).entitlements
INFO_PLIST = $(shell pwd)/Info.plist

.PHONY: build bundle sign run clean kill rebuild

## Build Swift code
build:
	swift build

## Create .app bundle from compiled binary
bundle: build
	@echo "→ Creating .app bundle..."
	@mkdir -p "$(APP_PATH)/Contents/MacOS"
	@mkdir -p "$(APP_PATH)/Contents/Resources"
	@cp "$(BINARY)" "$(APP_PATH)/Contents/MacOS/$(APP_NAME)"
	@cp "$(INFO_PLIST)" "$(APP_PATH)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(APP_PATH)/Contents/Resources/AppIcon.icns"; echo "→ Icon copied"; fi
	@echo "→ Bundle created at $(APP_PATH)"

## Sign with stable self-signed cert (prevents macOS from re-prompting permissions each launch)
SIGN_IDENTITY = ActionItems Dev
sign: bundle
	@echo "→ Signing..."
	@codesign --force --deep --sign "$(SIGN_IDENTITY)" \
		--entitlements "$(ENTITLEMENTS)" \
		"$(APP_PATH)"
	@echo "→ Signed OK"

## Kill any running instance
kill:
	@pkill -x $(APP_NAME) 2>/dev/null || true

## Build, sign, and launch
run: kill sign
	@echo "→ Launching $(APP_NAME)..."
	@open "$(APP_PATH)"
	@echo "→ Done! Look for the ✓ icon in your menu bar."

## Rebuild from scratch (clears .build cache)
rebuild: clean run

## Create distributable DMG
DMG_PATH = $(shell pwd)/ActionItems.dmg
dmg: sign
	@echo "→ Creating DMG..."
	@rm -f "$(DMG_PATH)"
	@hdiutil create -volname "ActionItems" -srcfolder "$(APP_PATH)" -ov -format UDZO "$(DMG_PATH)"
	@echo "→ DMG ready: $(DMG_PATH)"

## Full clean
clean: kill
	@rm -rf .build "$(APP_PATH)" "$(DMG_PATH)"
	@echo "→ Cleaned"
