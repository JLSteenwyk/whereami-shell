APP      := WhereAmI
BUILD    := build
BUNDLE   := $(BUILD)/$(APP).app
BINARY   := $(BUNDLE)/Contents/MacOS/$(APP)
APP_DEST := $(HOME)/Applications/$(APP).app

.PHONY: test install app install-app run-app clean

test:
	./tests/run.sh

install:
	./install.sh

# macOS menu bar app (requires Xcode command line tools for swiftc)
app: $(BINARY)

$(BINARY): macos/WhereAmI.swift macos/Info.plist
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp macos/Info.plist $(BUNDLE)/Contents/Info.plist
	swiftc -O -framework Cocoa -framework ServiceManagement -o $(BINARY) macos/WhereAmI.swift
	codesign --force --sign - $(BUNDLE) 2>/dev/null || true

install-app: app
	mkdir -p $(HOME)/Applications
	rm -rf $(APP_DEST)
	cp -R $(BUNDLE) $(APP_DEST)
	@echo "installed $(APP_DEST); launching"
	open $(APP_DEST)

run-app: app
	open $(BUNDLE)

clean:
	rm -rf $(BUILD)
