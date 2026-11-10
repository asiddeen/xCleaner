export TMPDIR := /tmp
export CLANG_MODULE_CACHE_PATH := /tmp/xcleaner-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE := /tmp/xcleaner-swiftpm-cache
SWIFT_CACHE_FLAGS = --disable-sandbox --cache-path /tmp/xcleaner-spm-cache -Xswiftc -module-cache-path -Xswiftc /tmp/xcleaner-swift-cache -Xcc -fmodules-cache-path=/tmp/xcleaner-clang-cache

.PHONY: all build release test app dmg run clean

all: app dmg

build:
	swift build $(SWIFT_CACHE_FLAGS)

release:
	swift build -c release --arch arm64 $(SWIFT_CACHE_FLAGS)

test:
	swift test $(SWIFT_CACHE_FLAGS)

app:
	bash scripts/bundle-app.sh

dmg:
	bash scripts/package-dmg.sh

run: app
	open dist/xCleaner.app

clean:
	swift package clean
	rm -rf dist /tmp/xcleaner-swift-cache /tmp/xcleaner-clang-cache
