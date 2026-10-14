# Preview validation — 14 October 2026

Source: 80be942c2ce0fd555673bb02f46c528e8115a699.

- 72 Swift Testing cases in 12 suites passed on the local Apple Silicon Mac, including crash recovery and regression coverage from independent ECC review.
- Nine validation cases passed against intentionally damaged copies of the universal app bundle.
- Both arm64 and x86_64 release binaries compiled, with macOS 14.0 deployment target and a verified ad-hoc signature.
- Native UI: four-file preview, sort and Undo restored original bytes; English/dark and Russian/light observed. The revised preview cancellation was verified with a flat folder of 10,000 files; cancellation returned to the idle screen without a plan.
- Debug benchmark on Apple Silicon/macOS 15.7.1, 10,000 files of 128 bytes: preview 34.386 seconds, sort 26.971 seconds, Undo 34.614 seconds. Zero failures; all 10,000 restored contents verified. These are single-run timings, not performance guarantees. Peak memory was not measured.
- GitHub CI run [38631122759](https://github.com/dmsznv-dot/tidyfolder/actions/runs/38631122759) built the universal app and ZIP/DMG. The downloaded artifact digest, both archive checksums, and the extracted app's architecture/metadata/signature were verified locally.
- Publication uses those exact reviewed CI archives, pinned by source commit, run ID and SHA-256; it does not rebuild a different binary for release.

Remaining checks: native UI on Intel and macOS 14, VoiceOver, Reduce Motion, minimum window layout, a real physical cross-volume move and Undo, and Developer ID/notarization/Gatekeeper acceptance. Local disk-image services were unavailable; DMG creation succeeded in CI, while mounting/installation has not been verified locally.

The release remains an ad-hoc signed, unnotarized preview. Proprietary Folder Tidy matching predicates are independently approximated; exhaustive parity is not claimed.
