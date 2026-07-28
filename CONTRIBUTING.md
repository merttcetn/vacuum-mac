# Contributing

Vacuum handles destructive operations, so safety invariants take precedence over
the amount of space a rule can find.

## Development setup

Use macOS 14 or newer, Xcode 16.4 or newer, and XcodeGen 2.46.0. Generate
`Vacuum.xcodeproj` from `project.yml`; do not hand-edit generated project data.

```sh
scripts/install-xcodegen.sh
export PATH="${TMPDIR:-/tmp}/vacuum-xcodegen/bin:${PATH}"
xcodegen generate --spec project.yml
xcodebuild \
  -project Vacuum.xcodeproj \
  -scheme Vacuum \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  test
```

CI treats Swift and compiler warnings as errors and also builds an unsigned
universal executable.

## Rule changes

Every scanner rule must use a narrow, documented root and have positive and
negative fixtures. A rule must explain why data is disposable and what it costs
to recreate. Never classify credentials, session state, user output, ambiguous
paths, or unverified project folders as Safe.

A cleanup-affecting pull request must cover:

- classification and default selection;
- required manifests or lockfiles;
- relevant process guards;
- symlink, containment, and resource-identity behavior; and
- cancellation where traversal volume changes.

Do not add subprocess calls, remote rule catalogs, background cleanup, broad
`build`/`dist` rules, or traversal that follows symlinks.

## Pull requests

Keep changes focused and describe the user-visible effect. Run the full test suite
and an unsigned universal build before requesting review. Changes that enable or
broaden deletion need an explicit safety review.

## Release maintainers

The `release` GitHub environment must require approval and define:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Base64 Developer ID certificate and private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the PKCS#12 archive |
| `DEVELOPER_ID_APPLICATION` | Full Developer ID Application signing identity |
| `DEVELOPMENT_TEAM` | Apple Developer Team ID used by Xcode |
| `NOTARY_APPLE_ID` | Apple ID used by `notarytool` |
| `NOTARY_PASSWORD` | App-specific password for notarization |
| `NOTARY_TEAM_ID` | Team ID passed to `notarytool` |
| `SPARKLE_PRIVATE_KEY_BASE64` | Base64 contents of the exported Sparkle EdDSA private key |

Generate the Sparkle key once with the tools from the pinned Sparkle distribution.
Export it with `generate_keys -x`, protect the private file offline, and place only
its base64 representation in the protected release environment. The matching
public key is committed in `Config/Info.plist`; release validation checks it before
signing.

Before pushing a release tag:

1. verify the version and build number in `project.yml`;
2. confirm CI passes on `main`;
3. create a tag such as `v0.1.0-beta.1`; and
4. review the resulting signature, notarization log, checksums, and appcast.

GitHub Releases hosts ZIP/DMG assets. GitHub Pages publishes `appcast.xml`.
