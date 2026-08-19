PRODUCT_NAME := BZAdBlocker
MIN_IOS ?= 13.0
ARCH ?= arm64
BUILD_DIR := build
OUTPUT := $(BUILD_DIR)/$(PRODUCT_NAME).dylib
SOURCES := $(shell find Sources -name '*.m' -print | sort)

SDKROOT ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
CLANG ?= $(shell xcrun --sdk iphoneos --find clang 2>/dev/null)

CFLAGS := -x objective-c -fobjc-arc -fmodules -fvisibility=hidden \
	-isysroot "$(SDKROOT)" -arch $(ARCH) -miphoneos-version-min=$(MIN_IOS) \
	-ISources/BZAdBlocker -ISources/BZMenuKit -ISources/BZMenuKit/include \
	-Wall -Wextra -Wno-deprecated-declarations

LDFLAGS := -dynamiclib -ObjC \
	-Wl,-install_name,@rpath/$(PRODUCT_NAME).dylib \
	-framework Foundation -framework UIKit -framework QuartzCore

.PHONY: all clean validate check-toolchain

all: validate check-toolchain $(OUTPUT)

validate:
	python3 scripts/validate_project.py

check-toolchain:
	@test -n "$(SDKROOT)" -a -d "$(SDKROOT)" || (echo "error: iPhoneOS SDK not found; install Xcode and select it with xcode-select"; exit 1)
	@test -n "$(CLANG)" -a -x "$(CLANG)" || (echo "error: Apple clang not found"; exit 1)

$(OUTPUT): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	"$(CLANG)" $(CFLAGS) $(SOURCES) $(LDFLAGS) -o "$@"
	@command -v strip >/dev/null && strip -x "$@" || true
	@command -v codesign >/dev/null && codesign --force --sign - "$@" || true
	@file "$@"

clean:
	rm -rf $(BUILD_DIR)
