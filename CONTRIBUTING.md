# Contributing to xCleaner

Thank you for your interest in contributing to **xCleaner**! xCleaner is built with Swift 6, SwiftUI, and AppKit on Apple Silicon macOS.

---

## 🛡️ Core Safety Principles (Non-Negotiable)

xCleaner is designed for safety first. Any PR or contribution touching scanning or execution must uphold the **5-Layer Safety Contract**:
1. **Never Delete macOS System Roots**: `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, and core OS directories are strictly blocked.
2. **Never Touch Version Control or Credentials**: All `.git` folders, cryptographic keys (`*.pem`, `*.key`, `*.keystore`), and cloud/registry tokens must remain protected.
3. **Respect Running App Locks**: Never stage or clean active files for an application currently running in macOS.
4. **Current / Default Versions Are Locked**: Default toolchains (`nvm alias default`, active Node `NVM_BIN`, latest stable Gradle, current stable Android SDK) must never be staged or deleted.
5. **No Silent Deletions**: The user is always in control; all cleanup operations must go through the user-visible Cleanup Queue and move to Trash by default.

---

## 🏗️ Architecture Overview

- **`Sources/XCleanerCore`**: Pure Swift business logic and CLI scanning services:
  - `Models/`: Data structures (`InstalledAppBundle`, `ToolchainItem`, `VolumeMetrics`, `CleanupRecord`).
  - `Safety/`: `SafetyPolicyEngine`, `RunningAppGuard`, `KeepListStore`, `AdvisoryEngine`.
  - `Scanning/`: `APFSVolumeMonitor`, `SmartJunkScanner`, `AppUninstallerScanner`, `ToolchainVersionScanner`, `ConcurrentDiskScanner`.
  - `DockerAndRemote/`: Local Docker and remote SSH discovery and safe prune execution.
  - `Execution/`: `CleanupService` (pre-flight TOCTOU verification and Trash recycling).
- **`Sources/xCleaner`**: Native macOS UI built with SwiftUI and AppKit:
  - `State/`: `AppViewModel`, `NotificationManager`, `MenuBarController`.
  - `Views/`: `MainShellView`, `StoragePulseView`, `SmartJunkView`, `AppUninstallerView`, `ToolchainsAndDockerView`, etc.

---

## 🛠️ Development Setup & Local Commands

xCleaner requires **macOS 14+** on **Apple Silicon** with Apple Command Line Tools (`swift --version` >= 6.0). No `Xcode.app` install is required.

```bash
# 1. Run unit & safety integration test suite
make test

# 2. Build local ad-hoc signed .app bundle
make app

# 3. Package distributable drag-and-drop .dmg installer
make dmg

# 4. Launch the application
make run
```

---

## 🧪 Testing Guidelines

- Write tests using the native **Swift Testing** framework (`import Testing`) rather than XCTest so builds succeed seamlessly in headless CLI environments.
- Ensure all safety invariants pass before opening a pull request:
  ```bash
  make test
  ```

---

## 🏷️ Credits

Built with precision and pair-programmed with **Google Antigravity**.
