# TidyFolder

A native macOS file organizer written in Swift 6.2, SwiftUI and AppKit. Preview where files will go, organize with ordered rules, and restore files from persistent history.

[Русская документация](README.ru.md) · [Downloads](https://github.com/dmsznv-dot/tidyfolder/releases) · [Compatibility](docs/compatibility.md)

The first distribution is a **0.1.1 preview**. It is independently implemented and is not affiliated with Folder Tidy or Tunabelly Software. Visible category names were checked against the original; proprietary matching predicates have not been reproduced or verified exhaustively.

Requires macOS 14 or newer. Universal packaging supports Apple Silicon and Intel; local runtime verification covers Apple Silicon on macOS 15.7.1. The preview uses ad-hoc signing and is **not Apple notarized**. Gatekeeper may block downloaded copies. A Developer ID signed, notarized release requires the maintainer's Apple Developer credentials.

Choose a source and destination, press Preview, review every proposed destination, then Organize. If both folders are the same, files go into category subfolders. Rules use the first enabled match; custom rules support nested all/any/none groups and typed name, extension, type, kind, size, date and tag conditions. History survives restart. Undo refuses to replace occupied original paths or move files whose identity/content changed.

No application network access, telemetry or third-party runtime dependencies. Preferences and SQLite history are stored in `~/Library/Application Support/TidyFolder`. Diagnostic logs are optional and can contain filenames and paths. The journal must remain available for recovery. In ambiguous crash states, both copies are retained for inspection.

```sh
./scripts/swift.sh test --no-parallel
./scripts/build-app.sh universal
EXPECTED_ARCH=universal python3 scripts/test-release.py
./scripts/package-release.sh 0.1.1
```

Swift 6.2+ is required. Full Xcode and Command Line Tools are supported; the wrapper selects project-local caches and supplies Swift Testing framework paths on CLT. Universal binaries are compiled separately and combined with `lipo`, so full Xcode is not required for compilation. DMG creation needs macOS disk-image services.

`SIGNING_MODE=developer-id` requires `SIGNING_IDENTITY`; packaging additionally requires a configured `NOTARY_PROFILE`. Missing credentials fail explicitly. CI builds a preview and validates tests and damaged bundles. The release workflow creates a draft for review. See [release checklist](docs/release-checklist.md) and [native UI observations](docs/manual-qa.md).

File replacement is prevented with exclusive filesystem operations. Cross-volume copies are verified before source removal; a durable intent journal supports interrupted-run recovery. These checks do not provide an absolute guarantee against unrelated programs modifying the same directories during a run. Cloud placeholders and symbolic links are not followed. Default scanning treats application/document packages as opaque.

MIT licensed. Report issues with a reproducible disposable fixture and redact private filenames/paths.
