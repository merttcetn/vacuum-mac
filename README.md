# Vacuum

Vacuum is a native macOS menu-bar utility for understanding developer storage. It
classifies recreatable data as **Safe**, **Review**, or **Protected**, explains the
cost of rebuilding it, and keeps the user in control.

The first release is a read-only scanner. Cleanup will remain disabled until the
filesystem safety suite is proven against real-world dogfood data.

## What Vacuum scans

- Codex profiles, while excluding credentials, configuration, sessions, history,
  databases, skills, plugins, packages, and user output
- Recreatable caches from Claude, Cursor, Gemini, OpenCode, npm, node-gyp, uv,
  Homebrew, Mole, Xcode, Playwright, and dotslash
- Hugging Face, Whisper, Ollama, and LM Studio models on a per-model basis
- Approved project roots for verified `node_modules`, `.build`, `.dart_tool`,
  `.venv`/`venv`, and `Pods` artifacts

Model caches, project artifacts, `_npx`, dotslash artifacts, and Codex cache data
always require review and start unselected. Protected items are visible but cannot
be selected.

## Safety model

Vacuum ships a fixed, local rule catalog. It does not download deletion rules,
invoke a shell, call Mole, or run package-manager commands. It does not follow
symlinks.

Immediately before cleanup, Vacuum checks that every item:

1. is still under a user-approved root;
2. is owned by the current user;
3. has the same device and inode observed during scanning; and
4. is not guarded by a running related process.

Trash is the default operation and is reported as moved/pending reclaim rather
than freed space. Vacuum tracks only items it moved. Restore never overwrites an
existing path, and purge or permanent cleanup requires a 1.5-second confirmation.
History keeps path details locally for 30 days. There is no telemetry and no
automatic cleanup.

## Requirements

- macOS 14 or newer
- Xcode 16.4 or newer with Swift 6
- [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)

Sparkle 2.9.4 is pinned exactly. Sparkle update checks are the app's only network
access and can be disabled in Settings.

## Build

```sh
scripts/install-xcodegen.sh
export PATH="${TMPDIR:-/tmp}/vacuum-xcodegen/bin:${PATH}"
xcodegen generate --spec project.yml
xcodebuild \
  -project Vacuum.xcodeproj \
  -scheme Vacuum \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

If XcodeGen is already installed, confirm `xcodegen --version` reports exactly
`2.46.0` and run the generation command directly.

## Test

```sh
xcodebuild \
  -project Vacuum.xcodeproj \
  -scheme Vacuum \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  test
```

The test suite covers classification fixtures, manifest validation, protected
Codex data, symlink and path-swap defenses, process guards, hardlink accounting,
cancellation, read-only enforcement, restore collisions, Vacuum-only purge, and
history expiry.

## Release

Tags matching `v*` start the signed release workflow. The first planned release is
`v0.1.0-beta.1`. The workflow produces universal arm64/x86_64 ZIP and DMG files,
notarizes and staples them, verifies Gatekeeper acceptance, generates a signed
Sparkle appcast, and publishes SHA-256 checksums.

Release environment secrets are documented in
[CONTRIBUTING.md](CONTRIBUTING.md#release-maintainers).

## Privacy and permissions

Vacuum collects no analytics and sends no scanned paths anywhere. Standard user
permissions are used by default. Full Disk Access is optional and should only be
considered for a user-selected target that macOS denies; there is no privileged
helper.

## License

Apache License 2.0. See [LICENSE](LICENSE).
