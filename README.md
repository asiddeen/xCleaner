# xCleaner

**xCleaner** is a lightweight (`~4.7 MB`), native Apple Silicon (`arm64`) macOS storage analyzer and safe cleanup assistant built with **Swift 6**, **SwiftUI**, and **AppKit** — zero Electron bloat, zero background CPU polling, and 100% user-driven cleanup decisions.

## Highlights

- **Storage Pulse**: Real-time APFS container breakdown (`User & App Data`, `VM Swap`, `System & Preboot`, `Purgeable`, `Raw Free`, and `tmutil` local Time Machine snapshots) + macOS TCC Privacy Gap estimator + 1-click Full Disk Access deep-link.
- **Smart Junk & Monorepo Artifact Scanner**:
  - `~/Library/Caches`, `~/Library/Logs`, and abandoned auto-updater staging bundles (`*.ShipIt`, `*-updater`).
  - Surgical `Application Support` browser & IDE cache isolation (Chromium `Service Worker/CacheStorage` & GPU/Shader caches without touching `Cookies`, `Login Data`, `Bookmarks`, `History`, `Local Storage`, or `IndexedDB`; Spotify `PersistentCache` with offline-songs advisory).
  - Global developer & AI caches (`npm/_cacache`, `_npx`, `Homebrew`, `pip`, `uv`, `CocoaPods`, `SwiftPM`, `go-build`, `DerivedData`, `HuggingFace`, `Ollama`, `antigravity-backup`).
  - Depth-7 monorepo project build/dependency scanner (`node_modules`, `dist`, `android/app/build`, `.next`, `.angular/cache`, `Pods`, `.build`, `target`, `venv`, R `renv`) with project staleness filters (`All`, `>30d`, `>60d`, `>90d`, `>180d`).
  - Cross-location uninstalled app detector (`Application Support/Code` + `~/.vscode`, etc.) with expandable granular sub-items (`.safe` `.vsix`/logs vs `.warning` extensions/settings).
- **Side-by-Side Toolchains & Remote SSH Docker**:
  - Compares installed Gradle versions (`~/.gradle/caches` + `wrapper/dists` + leftover `jdks/*.tar.gz`), Android SDK/NDK/build-tools (flagging `-rc*`/previews), Node `nvm` runtimes, and Puppeteer/Playwright headless browsers — automatically locking your default & current versions while cross-referencing older versions against active projects (`gradle-wrapper.properties`, `.nvmrc`).
  - Inspects local `Docker.raw` and remote SSH servers from `~/.ssh/config`, running safe user-confirmed `docker builder prune -f` and `docker image prune -f` without touching running containers or volumes.
- **Visual Folder Explorer**: Synchronized `ncdu`-style ranked size-bar list + interactive SwiftUI `Canvas` Squarified Treemap with breadcrumb drill-down.
- **5-Layer Safety Contract**: Zero root `rm`, hardcoded system/credential/VCS/cloud blocklist, live running-app & `SingletonLock` guard with graceful app quit, `Pin to Keep` (`KeepListStore`), Move-to-Trash by default + explicit acknowledgment gates on Warning/Permanent cleanups, and persistent JSONL audit history (`~/Library/Application Support/xCleaner/cleanup-history.jsonl`).

## Build, Test & Run (No Xcode.app Required)

Requires macOS 14+ on Apple Silicon with Apple Command Line Tools (`swift` 6.0+):

```bash
# Run unit & safety integration tests
make test

# Build ad-hoc signed Apple Silicon bundle at dist/xCleaner.app
make app

# Launch xCleaner.app (or copy dist/xCleaner.app to /Applications)
make run
```
