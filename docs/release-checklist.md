# Release checklist

- Run the whole Swift Testing suite and native app build on Swift 6.2+.
- Check preview → sort → undo using a disposable native UI fixture.
- Build arm64 and x86_64, combine with lipo, validate bundle metadata, deployment target, localizations and signature.
- Run `scripts/test-release.py` against the actual bundle; it deliberately damages independent copies.
- Run crash checkpoints and the cross-volume branch tests; distinguish simulated cross-volume from two physical volumes.
- Benchmark 10,000 files with `./scripts/swift.sh build --product TidyHarness`, then `/usr/bin/time -l .build-working/debug/TidyHarness --benchmark /path/to/disposable/workspace`.
- Review the whole branch with independent ECC code-reviewer/security-reviewer instructions; resolve material findings.
- Verify GitHub CI and checksums on a clean extracted download.
- Mark unnotarized builds as previews. Never claim Developer ID signing without certificate verification.
- For signed CI, configure `DEVELOPER_ID_CERTIFICATE_BASE64`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `BUILD_KEYCHAIN_PASSWORD`, `SIGNING_IDENTITY`, `NOTARY_APPLE_ID`, `NOTARY_APP_PASSWORD`, `APPLE_TEAM_ID`; dispatch the release workflow explicitly with signed enabled against the version tag.
- Review draft attachments before publishing. Publish only after the actual archive passes verification.

Known host constraint: creating a test APFS image with hdiutil failed with “Device not configured” in the managed environment. Physical two-volume checks and local DMG generation must not be reported as passed. ZIP generation does not require disk-image services.
