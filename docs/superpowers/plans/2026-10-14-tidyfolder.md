# TidyFolder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Выпустить нативный macOS-организатор файлов с правилами, предпросмотром и долговечным восстановлением, исходниками и скачиваемыми сборками в `dmsznv-dot/tidyfolder`.

**Architecture:** Swift Package разделяет чистые модели/правила, файловые адаптеры, журнал SQLite и UI. Один ExecutionCoordinator управляет sort/undo через явный run gate; мутации имеют долговечный intent и восстановление по фактическому состоянию диска. SwiftUI использует AppKit для выбора папок и Finder.

**Tech Stack:** Swift 6.2, macOS 14+, SwiftUI, AppKit, Foundation, UniformTypeIdentifiers, CryptoKit, Darwin, системная SQLite, Swift Testing, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-14-tidyfolder-design.md` — согласована пользователем 14 октября; дополнение: Swift сейчас, возможное отдельное переписывание для Windows позднее, репозиторий уже создан.

## Global Constraints

- macOS 14+, Swift 6.2; UI около 1080 × 720, минимальное читаемое окно 820 × 560.
- Русский и английский интерфейсы; светлая/тёмная системные темы, keyboard, VoiceOver, Reduce Motion.
- MIT; локальная сортировка без аккаунта и backend; пользовательские файлы не отправляются в сеть.
- Существующие файлы никогда не перезаписываются автоматически; изменённые/неоднозначные объекты не удаляются.
- Правила «все/любое/ни одно», относительное назначение, первое совпавшее включённое правило; неподошедшие файлы остаются на месте.
- Сначала работающий Swift-релиз; Windows-код и переносимый runtime не создаются. JSON settings и fixtures имеют версию и документированный смысл для будущего порта.
- Журнал SQLite WAL + synchronous=FULL; unsupported exclusive rename не заменяется обычным rename.
- Проверенная подпись/notarization не заявляется без Developer ID; Intel совместимость не заявляется без соответствующей сборки/проверки.
- GitHub-репозиторий пуст: существующий код и AGENTS.md отсутствуют. Публикация docs разрешена текущим запросом; продуктовая реализация начинается после review этого плана.

## Review Focus

- Другой процесс создаёт файл назначения между preview и move: syscall отказывает в замене (Task 4).
- Правило изменяется после preview: UI инвалидирует план, исполнение использует immutable snapshot настроек (Tasks 3, 9).
- Два окна/actor reentrancy запускают sort и undo: один общий run gate отклоняет второй запуск (Task 6).
- Журнал имеет более новую схему или повреждён: UI показывает ошибку, мутации не начинаются (Tasks 5, 8, 9).
- Приложение закрывается после публикации копии, до удаления источника: recovery сохраняет оба объекта до однозначной сверки (Tasks 6, 7).

## Structure and task dependencies

`Sources/TidyCore/Rules`, `Planning`, `FileSystem`, `Journal`, `Execution`, `Settings` содержат соответствующие роли. `Sources/TidyFolderApp` содержит SwiftUI и app composition; `Sources/TidyHarness` — дочерний процесс для аварийных тестов. `Sources/CSQLite` связывает системный sqlite3. Тесты находятся в `Tests/TidyCoreTests`; app metadata/localizations — в `Resources`; сборка — в `scripts`; CI — в `.github/workflows`.

Порядок: Task 1 → 2 → 3; Task 4 и 5 зависят от 1; Task 6 использует 3/4/5; Task 7 использует 6; Task 8 использует 1; Task 9 использует 2–8; Task 10 использует всё. Настройка package, fixtures и документация включаются в первую задачу, которой они нужны.

### Task 1: Типизированные правила и тестируемый Swift Package

**Files:** `Package.swift`, `Sources/TidyCore/Rules/RuleModels.swift`, `RuleEngine.swift`, `Tests/TidyCoreTests/RuleEngineTests.swift`, `.gitignore`.

**Interfaces:** Produces `Rule: Codable, Sendable` (id: UUID, name: String, enabled: Bool, destination: String, group: RuleGroup); indirect `RuleNode` (.condition(RuleCondition), .group(RuleGroup)); `RuleGroup` (mode: .all/.any/.none, children: [RuleNode]); `RuleCondition` with typed text/type/extension/size/date/tags/kind cases; `FileKind` (.regularFile/.directory/.package/.alias/.symlink); `FileMetadata` (name, extension, typeIdentifier, kind, size, createdAt, modifiedAt, tags); `RuleMatch` (ruleID, destination). `RuleEngine.match(metadata: FileMetadata, rules: [Rule], now: Date) -> RuleMatch?`.

- [ ] Write failing tests `firstEnabledMatchWins`, `nestedNoneGroup`, `sizeBoundaryInclusive`, `relativeDateUsesInjectedClock`, `unicodeNameComparison`, `codableRoundTrip`; assert precedence, non-vacuous input behavior and deterministic now. Test anchor: `#expect(RuleEngine.match(metadata: invoicePDF, rules: [disabledRule, invoiceRule, pdfRule], now: fixedDate)?.ruleID == invoiceRule.id)`.
- [ ] Run `swift test --filter RuleEngineTests`; confirm a missing-symbol/module failure before adding implementation.
- [ ] Create package targets for TidyCore, app and harness only as needed; implement the typed models and pure RuleEngine. Define empty group behavior explicitly: invalid rule, never matches; retain integer byte units and UTC instants in JSON.
- [ ] Run `swift test --filter RuleEngineTests`; all cases pass with no filesystem access.
- [ ] Commit `feat: add typed sorting rules and rule engine`; ECC code-reviewer checks the actual diff.

### Task 2: Встроенные категории и совместимость с оригиналом

**Files:** `Sources/TidyCore/Rules/BuiltinRules.swift`, `FileTypeClassifier.swift`, `Tests/TidyCoreTests/BuiltinRulesTests.swift`, `Tests/TidyCoreTests/Fixtures/rule-cases.json`, `docs/compatibility.md`.

**Interfaces:** Consumes Task 1; produces `BuiltinRules.catalog(localeIdentifier: String) -> [Rule]`, `FileTypeClassifier.typeIdentifier(forExtension: String) -> String?`. Stable rule IDs/folder names do not change for a saved catalog when language changes.

- [ ] Write `categorizesCurrentDocumentedTypes`, `foldersAndAliasesDisabledByDefault`, `allOnKeepsSpecialRulesOff`; anchor: `#expect(match("invoice.md").destination == "Markdown")`, likewise epub → eBooks, obj → 3D Models and eml → Emails. Fixtures include PDFs, images, videos, audio, spreadsheets and unknown types.
- [ ] Run `swift test --filter BuiltinRulesTests`; expect missing catalog/classifier failures.
- [ ] Implement native UTType classification plus explicit extension supplements; obtain the current built-in category list from original public screenshots/trial and document supported/verified/gap per row. Never label an unsurveyed list as exact parity; unresolved rows block the full-clone claim.
- [ ] Run tests; review fixture report against the original's current category list and rule semantics, including tags. Unsupported objects have a reason, not a made-up match.
- [ ] Commit `feat: add built-in categories and compatibility fixtures`.

### Task 3: Неизменяемый предпросмотр и безопасный обход

**Files:** `Sources/TidyCore/Planning/FileSnapshot.swift`, `ScanOptions.swift`, `DirectoryScanner.swift`, `ScanPlanner.swift`, `DestinationValidator.swift`, `Tests/TidyCoreTests/ScanPlannerTests.swift`.

**Interfaces:** Consumes Rules; produces `FileIdentity` (device: UInt64, inode: UInt64), `FileFingerprint` (identity, size: UInt64, modificationNanoseconds: Int64), `FileSnapshot` (url, fingerprint, metadata, isDirectory/isPackage/isSymlink/isAlias/isUnavailable flags); `ScanOptions: Codable, Sendable` (recursive, tagged policy, emptyFolders, skipBundles, removeEmptyFolders, datedRoot, excludedURLs, conflictPolicy .skip/.keepBoth); `PlannedOperation` (id, source: FileSnapshot, destination: URL, ruleID); `TidyPlan` (id, sourceRoot, destinationRoot, options, rules, operations, skips, createdAt); `ScanPlanner.plan(source: URL, destination: URL, rules: [Rule], options: ScanOptions, now: Date) async throws -> TidyPlan`.

- [ ] Write `previewDoesNotMutate`, `excludesNestedDestination`, `sameRootExcludesOutputFolders`, `neverFollowsSymlinkCycle`, `packagesOpaque`, `excludesSubtree`, `rejectsTraversalDestination`, `reservesDuplicateNames`, `placeholdersSkipped`, `datedRootUnique`; assert file tree/content unchanged after plan. Assert `destination ../outside` fails before enumeration.
- [ ] Run `swift test --filter ScanPlannerTests`; confirm failures before planner implementation.
- [ ] Implement lstat-based identities, metadata snapshots and component-wise ancestor checks. Reject symlink destination parents and a folder moving into its descendant. Exclude destination trees, app stores and explicit exclusions; hidden item policy follows the spec. Empty source/zero enabled rules yields an empty plan and no mutating run.
- [ ] Run tests; capture fingerprint and settings snapshots in every plan so later changes cannot silently alter destinations.
- [ ] Commit `feat: add read-only planning and traversal boundaries`.

### Task 4: Проверенные файловые primitives без перезаписи

**Files:** `Sources/TidyCore/FileSystem/FileSystem.swift`, `LocalFileSystem.swift`, `FileVerification.swift`, `Tests/TidyCoreTests/FileSystemTests.swift`.

**Interfaces:** Consumes FileSnapshot/Fingerprint. Produces `FileSystem: Sendable` protocol with `snapshot(at: URL) throws -> FileSnapshot`, `renameExclusive(from: URL, to: URL) throws`, `copyExclusive(from: URL, to: URL) throws`, `verifyCopy(source: URL, copy: URL, expected: FileFingerprint) throws -> VerificationEvidence`, `synchronize(at: URL) throws`, `removeSource(at: URL, expected: VerificationEvidence) throws`, `createDirectoryExclusive(at: URL) throws`, `removeDirectoryIfEmpty(at: URL) throws`; `VerificationEvidence` stores source fingerprint and streamed SHA-256 plus required metadata evidence. Throws typed `FileOperationError`, including conflict, changed, unsupported, permissions and I/O.

- [ ] Write `destinationRaceNeverReplaces`, `copyFailureKeepsSource`, `verificationRejectsModifiedSource`, `preservesTagsAndResourceFork`, `unsupportedRenameFailsClosed`, `caseCollisionKeepsBoth`, `readonlyFailureIsReported`; anchor: after failed exclusive move, assert both original file hashes unchanged.
- [ ] Run `swift test --filter FileSystemTests`; expect missing primitives failures.
- [ ] Implement Darwin exclusive rename rather than exists+move, operation-owned staging with exclusive creation, metadata-preserving copy, streaming hash, data synchronization and last-moment source validation. Directory/package copies verify a deterministic tree manifest with content hashes, link targets and required metadata; links are not followed. Reject unsupported objects/volumes instead of using weaker destructive fallbacks. Use NSFileCoordinator where required by supported provider-backed paths; do not claim protection from arbitrary external writers.
- [ ] Run tests; race a destination creation between scan and syscall; inspect actual tag/resource-fork preservation on APFS fixtures.
- [ ] Commit `feat: add exclusive file operations and copy verification`.

### Task 5: Долговечный SQLite журнал

**Files:** `Sources/CSQLite/module.modulemap`, `shim.h`, `Sources/TidyCore/Journal/JournalModels.swift`, `JournalStore.swift`, `SQLiteJournal.swift`, `Tests/TidyCoreTests/JournalTests.swift`.

**Interfaces:** Consumes TidyPlan/PlannedOperation/VerificationEvidence. Produces `OperationState` (.prepared, .copying, .verified, .publishIntent, .committed, .deleteIntent, .sourceRemoved, .completed, .conflict, .failed); Codable `RunRecord`, `OperationRecord`, `OperationEvidence`; `JournalStore: Sendable` async throws methods `prepare(plan: TidyPlan) -> RunRecord`, `transition(operationID: UUID, to: OperationState, evidence: OperationEvidence?)`, `finish(runID: UUID, result: RunSummary)`, `runs() -> [RunRecord]`, `operations(runID: UUID) -> [OperationRecord]`, `incompleteRuns() -> [RunRecord]`. `RunSummary` (runID, moved/copied/sourceRetained/skipped/failed counts, cancelled, issues).

- [ ] Write `reopenPreservesIntent`, `transitionWithEvidenceAtomic`, `invalidTransitionRejected`, `newerSchemaFailsClosed`, `corruptStoreFailsClosed`, `writeFailurePreventsMutation`; assert reopened operation paths/state/evidence identical.
- [ ] Run `swift test --filter JournalTests`; confirm missing store failure.
- [ ] Implement serialized SQLite access, versioned schema, prepared statements, WAL and synchronous=FULL; verify pragmas. Enable supported macOS fullfsync setting, document storage limitations. Persist directory ownership and reverse operation relationships; successful commit is required before caller mutates files.
- [ ] Run tests against a real temporary DB, close/reopen, injected write errors and malformed DB; corruption remains diagnosable and is not silently reset.
- [ ] Commit `feat: persist operation intents and history in SQLite`.

### Task 6: Исполнение, прогресс и аварийные checkpoints

**Files:** `Sources/TidyCore/Execution/ExecutionCoordinator.swift`, `RunEvent.swift`, `ExecutionCheckpoint.swift`, `Sources/TidyHarness/main.swift`, `Tests/TidyCoreTests/ExecutionTests.swift`, `CrashExecutionTests.swift`.

**Interfaces:** Consumes FileSystem, JournalStore and TidyPlan. Produces actor `ExecutionCoordinator.init(fileSystem: any FileSystem, journal: any JournalStore)`, `execute(plan: TidyPlan) async throws -> RunSummary`, `cancel() async`, `events() -> AsyncStream<RunEvent>`; `RunEvent` cases started/progress/issue/finished with runID. Explicit run gate remains held across awaits. `ExecutionCheckpoint` names each before/after journal and filesystem boundary; harness exits immediately at an injected checkpoint in a subprocess.

- [ ] Write `oneRunAcrossActorReentrancy`, `changedSincePreviewSkipped`, `cancelStopsNewOperations`, `zeroPlanDoesNotCreateRun`, `journalFailureStopsChanges`, `sameVolumeSort`, `crossVolumeCopyVerifyPublishDelete`; crash tests iterate every checkpoint and assert every input's data remains at source/staging/destination with journal evidence.
- [ ] Run `swift test --filter ExecutionTests` and `swift test --filter CrashExecutionTests`; confirm failures before implementation.
- [ ] Implement same-volume intent/exclusive rename/commit path and journaled cross-volume staging/verify/sync/publish/source-removal path. Persist mutation intent before each risky step; source retained yields copied/sourceRetained, not moved. Cancellation finishes critical publication/log sections and retains partial staging evidence for recovery; bounded serial mutation is the initial baseline.
- [ ] Run tests with injected errors and killed subprocesses; no unawaited task or MainActor I/O, no source deletion before verified publication evidence.
- [ ] Commit `feat: execute journaled runs with progress and cancellation`.

### Task 7: Восстановление и повторяемый undo

**Files:** `Sources/TidyCore/Execution/RecoveryEngine.swift`, `UndoPlanner.swift`, `Sources/TidyCore/Execution/ExecutionCoordinator.swift`, `Tests/TidyCoreTests/RecoveryTests.swift`, `CrashUndoTests.swift`.

**Interfaces:** Consumes OperationRecord/FileSystem/JournalStore; produces `RecoveryEngine.reconcile(runID: UUID) async throws -> RecoveryReport` (resolved, retained, conflicts); `UndoPlanner.plan(runID: UUID) async throws -> UndoPlan`; shared coordinator `undo(runID: UUID) async throws -> RunSummary`. Reverse intents use the same journal and exclusive primitives as sorting.

- [ ] Write `sortRestartUndoRestoresTree`, `occupiedOriginalPathPreservesBoth`, `editedDestinationRefusesUndo`, `replacedIdentityRefusesUndo`, `missingDestinationReported`, `secondUndoIdempotent`, `newFilesInCreatedFolderKept`, `hiddenMetadataRestored`, `crashUndoRestart`; assert same file contents/tags and original directory structure after a clean undo.
- [ ] Run `swift test --filter RecoveryTests` and `swift test --filter CrashUndoTests`; confirm failures first.
- [ ] Implement reconciliation for prepared/copying/verified/published/deleted states using persisted evidence and actual identities/content. Ambiguity is a conflict, never deletion. Undo persists reverse operations, stages hidden metadata safely for enabled empty-directory cleanup and only removes still-empty owned directories. Cleanup never recursively removes unowned content or an excluded repository.
- [ ] Run tests; include the crash between publication and source removal with both copies present and the cross-volume undo path.
- [ ] Commit `feat: recover interrupted runs and persist safe undo`.

### Task 8: Настройки, язык и формат для будущего порта

**Files:** `Sources/TidyCore/Settings/AppSettings.swift`, `SettingsStore.swift`, `SettingsMigration.swift`, `Tests/TidyCoreTests/SettingsTests.swift`, `docs/settings-format.md`.

**Interfaces:** Consumes Rule/ScanOptions; produces `AppSettings: Codable, Sendable` (schemaVersion: Int, rules, scanOptions, language .system/.ru/.en, appearance .system/.light/.dark, revealAfterRun, hideOtherApps, diagnosticLogging); actor `SettingsStore.init(url: URL)`, `load() async throws -> AppSettings`, `save(_ settings: AppSettings) async throws`. Direct distribution uses NSOpenPanel-selected paths and TCC; security-scoped bookmarks only when an explicitly sandboxed build requires them.

- [ ] Write `roundTripAllPredicates`, `atomicSaveFailureKeepsPrevious`, `rejectsFutureSchema`, `damagedSettingsDoesNotResetSilently`, `languageDoesNotRenameSavedDestinations`, `settingsJSONUsesStableIDs`; anchor: `#expect(try decode(encode(settings)) == settings)`.
- [ ] Run `swift test --filter SettingsTests`; confirm failures before store implementation.
- [ ] Implement versioned JSON with atomic replacement and validation. Document integer size units, UTC timestamps, operator meanings and stable rule IDs; no absolute machine-dependent paths in public example fixtures.
- [ ] Run tests including migration of supported versions and preservation of the previous valid settings on failed writes.
- [ ] Commit `feat: persist settings and document portable rule format`.

### Task 9: Нативный SwiftUI интерфейс и app composition

**Files:** `Sources/TidyFolderApp/TidyFolderApp.swift`, `AppModel.swift`, `Views/MainView.swift`, `SortView.swift`, `PreviewView.swift`, `RulesView.swift`, `RuleEditor.swift`, `HistoryView.swift`, `SettingsView.swift`, `FolderPicker.swift`, `Resources/en.lproj/Localizable.strings`, `ru.lproj/Localizable.strings`, `Resources/Info.plist`, `Tests/TidyCoreTests/PlanValidityTests.swift`, `docs/manual-qa.md`.

**Interfaces:** Consumes previous modules; `@MainActor @Observable AppModel` owns settings, navigation, active plan, history, progress, error; `preview() async`, `sort() async`, `cancel() async`, `undo(runID: UUID) async`, `invalidatePlan()`. AppModel uses the single coordinator; FileSystem APIs never execute on MainActor. `PlanValidity.isCurrent(plan: TidyPlan, settings: AppSettings, source: URL, destination: URL) -> Bool` is pure/testable.

- [ ] Write `ruleEditInvalidatesPlan`, `sourceChangeInvalidatesPlan`, `optionChangeInvalidatesPlan`; `#expect(!PlanValidity.isCurrent(plan: oldPlan, settings: editedRulesSettings, source: source, destination: destination))`.
- [ ] Run `swift test --filter PlanValidityTests`; missing helper should fail first.
- [ ] Implement the native app: sidebar Sort/Rules/History, NSOpenPanel and folder drop, preview table, nested typed rule editor, on/off + priorities, options/exclusions, dated root, progress/cancel, restart history/undo and diagnostics. Include reveal in Finder and optional hideOtherApps; use system typography/SF Symbols/menus, no fake browser traffic lights. Startup displays unresolved interrupted runs without automatic moves. Cmd+, settings, Cmd+O folder selection and keyboard table actions are supported.
- [ ] Run `swift test`, `swift build --product TidyFolder`; package/open app for manual light/dark 1080×720 and 820×560 QA, Russian/English, keyboard, Reduce Motion and VoiceOver. Record actual results; UI automation requires full Xcode and an actual run, not assumed PASS.
- [ ] Commit `feat: add native sorting rules and history interface`; ECC code-reviewer reviews UI and shared state.

### Task 10: Проверенный выпуск через GitHub

**Files:** `scripts/build-app.sh`, `package-release.sh`, `verify-release.sh`, `benchmark.swift`, `.github/workflows/ci.yml`, `release.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `README.md`, `README.ru.md`, `LICENSE`, `CHANGELOG.md`, `docs/release-checklist.md`.

**Interfaces:** `build-app.sh [arm64|x86_64|universal]` produces `dist/TidyFolder.app`; `package-release.sh VERSION` produces versioned ZIP/DMG/SHA256; `verify-release.sh APP_PATH` checks bundle ID `io.github.dmsznv-dot.tidyfolder`, executable, deployment target 14.0, version, architectures, resources and signing status. Signing mode is explicit; missing credentials cannot silently turn a requested signed release into an unsigned success.

- [ ] Create failing artifact assertions for missing executable/localizations, wrong version/architecture/minimum OS, invalid signature and a signed-mode run without secrets. Reuse the existing integration fixtures; do not add tests that only mirror shell lines.
- [ ] Run verification against intentionally incomplete bundles; expect nonzero exit and specific error before scripts are implemented.
- [ ] Implement app packaging with stock Apple tools. CI validates Swift 6.2+ availability on an explicitly selected macOS image, runs tests/build, uploads preview artifacts. Universal compile uses arm64/x86_64; Intel runtime compatibility stays unverified unless a corresponding runtime check runs. Release workflow creates a draft release from a version tag, generates checksums and optionally signs/notarizes/staples using CI secrets. No auto-publication before final artifact review. Pin actions to verified commit SHAs at implementation time.
- [ ] Run complete suite/build/artifact validation; run real two-volume sort/undo if test volumes are available; benchmark 10 000 small files and record timings/memory/hardware. Check GitHub CI and a clean download; include unsigned-preview status where appropriate. ECC code-reviewer + adapted security-reviewer perform whole-change review; resolve confirmed data-loss/release issues before publishing.
- [ ] Commit `build: add native app artifacts and GitHub release pipeline`; after review publish the concrete release authorized by the user, or clearly report the remaining credentials/runtime blockers.

## Plan self-review and execution handoff

Coverage: functions/categories → Tasks 1–3; safe moves → 4/6; durable history → 5; crash/undo/empty hidden folders → 6/7; saved rules/settings → 8; native UI/accessibility → 9; distribution/docs/benchmark → 10. Every task includes a failing test or verifiable artifact assertion, passing check and actual diff review. Signatures are defined before downstream use; Review Focus has owning tests.

Recommended execution: implementation in the current session with ECC roles used for focused architecture advice and independent review at meaningful module boundaries. This keeps shared Swift interfaces consistent and avoids a new implementer for every small file. Alternative: strict subagent-driven task-by-task implementation/review, with more handoffs and context cost. User reviews this document and selects the execution method before implementation, as required by Superpowers writing-plans.

Runner reference checked 14 October 2026: https://github.com/actions/runner-images . Current macOS labels and installed Xcode/Swift are checked again when writing workflows; deployment target 14.0 does not depend on a disappearing macOS-14 CI runner.
