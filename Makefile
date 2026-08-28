APP := build/LoudOrNot.app
# Installed under its display name so Finder lists it as "Loud or Not".
INSTALLED := /Applications/Loud or Not.app

# Without Xcode, swift-testing lives in the Command Line Tools developer directory
# instead of a platform SDK, so it has to be pointed at explicitly.
DEV_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
DEV_LIB := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
TEST_FLAGS := -Xswiftc -F -Xswiftc $(DEV_FW) \
	-Xlinker -F -Xlinker $(DEV_FW) \
	-Xlinker -rpath -Xlinker $(DEV_FW) \
	-Xlinker -rpath -Xlinker $(DEV_LIB)

.PHONY: all identity icon app install run stop test clean uninstall

all: install

identity:
	@./Scripts/create-identity.sh

# The generated .icns is committed, so this only needs rerunning when the art changes.
icon:
	@swift Scripts/make-icon.swift build/AppIcon.iconset
	@iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	@rm -rf build/AppIcon.iconset
	@echo "Wrote Resources/AppIcon.icns"

app: identity
	@./Scripts/bundle.sh

install: app
	@killall LoudOrNot 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@cp -R $(APP) "$(INSTALLED)"
	@open "$(INSTALLED)"
	@echo "Installed to $(INSTALLED) and running. Look for the waveform in the menu bar."

run: app
	@killall LoudOrNot 2>/dev/null || true
	@open $(APP)
	@echo "Running from $(APP)."

stop:
	@killall LoudOrNot 2>/dev/null || true

test:
	@swift test --disable-xctest --enable-swift-testing $(TEST_FLAGS)

uninstall: stop
	@rm -rf "$(INSTALLED)"
	@echo "Removed $(INSTALLED)"

clean:
	@rm -rf .build build
