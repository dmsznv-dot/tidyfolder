# Settings schema 1

`settings.json` is UTF-8, versioned by integer `schemaVersion: 1`. Writes replace the file atomically. Newer/unknown schemas and corrupt JSON fail explicitly; existing data is not silently reset. No older publicly released schema exists yet.

Rules have stable UUIDs, enabled/name/destination/builtin fields and a group tree (`all`, `any`, `none`). Conditions specify `field`, `comparison`, `value`. Byte sizes are nonnegative base-10 integer strings; relative date windows use days (86400 seconds), absolute date strings use ISO 8601 UTC. Text comparisons normalize canonical Unicode and ignore case. Type equality tests UTI conformance; Windows ports may substitute a native type registry while retaining explicit extension fixtures. Empty groups are invalid. First enabled match wins. A relative destination can contain nested folders but cannot be absolute or contain empty, `.` or `..` components.

Language and appearance affect UI only. Saved destination names are not renamed by changing language. Source/destination and exclusion URLs are local preferences, not portable example paths. The core has no dependency on AppKit; file identity is explicitly platform-specific, while rule semantics and sample cases are reusable in a future Windows implementation.
