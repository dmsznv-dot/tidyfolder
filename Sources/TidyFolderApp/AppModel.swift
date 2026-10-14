import SwiftUI
import AppKit
import Observation
import TidyCore

@MainActor @Observable final class AppModel {
    enum Section: String, CaseIterable { case sort, rules, history }
    var section: Section = .sort
    var settings = AppSettings()
    var plan: TidyPlan?
    var history: [RunRecord] = []
    var busy = false
    var loading = true
    var processed = 0
    var total = 0
    var currentFile = ""
    var message: String?
    var startupError: String?
    var lastSummary: RunSummary?
    var lastTidyID: UUID?
    @ObservationIgnored var journal: SQLiteJournal?
    @ObservationIgnored var coordinator: ExecutionCoordinator?
    @ObservationIgnored private var previewTask: Task<TidyPlan, Error>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored let dataRoot: URL
    @ObservationIgnored let store: SettingsStore
    init() {
        if let directory = ProcessInfo.processInfo.environment["TIDYFOLDER_DATA_DIR"] { dataRoot = URL(fileURLWithPath: directory, isDirectory: true) }
        else { dataRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TidyFolder", isDirectory: true) }
        store = SettingsStore(url: dataRoot.appendingPathComponent("settings.json"))
    }
    var russian: Bool { settings.language == .ru || settings.language == .system && (Locale.preferredLanguages.first?.hasPrefix("ru") == true) }
    func tr(_ en: String, _ ru: String) -> String { russian ? ru : en }
    var colorScheme: ColorScheme? { settings.appearance == .system ? nil : settings.appearance == .dark ? .dark : .light }
    var canPreview: Bool { !busy && !loading && startupError == nil && settings.sourceURL != nil && settings.destinationURL != nil }
    var canSort: Bool {
        guard canPreview, let p = plan, let source = settings.sourceURL, let destination = settings.destinationURL else { return false }
        return !p.operations.isEmpty && PlanValidity.isCurrent(plan: p, settings: settings, source: source, destination: destination)
    }
    func bootstrap() async {
        guard !bootstrapped else { return }; bootstrapped = true
        defer { loading = false }
        do {
            settings = try await store.load()
            let root = dataRoot
            let db = try await Task.detached {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                return try SQLiteJournal(url: root.appendingPathComponent("history.sqlite"))
            }.value
            journal = db
            let runner = ExecutionCoordinator(journal: db, protectedURLs: [root]); coordinator = runner
            history = try await db.runs().filter { $0.undoOfRun == nil }
            eventTask = Task { [weak self] in
                let events = await runner.events()
                for await event in events {
                    guard let self else { return }
                    switch event {
                    case .started(_, let n): total = n; processed = 0
                    case .progress(_, let done, let n, let file): processed = done; total = n; currentFile = file
                    case .issue(_, let text): message = text
                    case .finished: currentFile = ""
                    }
                }
            }
        } catch { startupError = error.localizedDescription }
    }
    func invalidatePlan() { plan = nil }
    func preferencesChanged() {
        invalidatePlan(); guard bootstrapped, startupError == nil, !loading else { return }
        saveTask?.cancel(); let snapshot = settings
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)); try Task.checkCancellation(); try await store.save(snapshot) }
            catch is CancellationError {} catch { message = error.localizedDescription }
        }
    }
    func choose(source: Bool) {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.title = source ? tr("Choose the folder to organize", "Выберите папку для сортировки") : tr("Choose the destination", "Выберите папку назначения")
        panel.prompt = tr("Choose folder", "Выбрать папку")
        panel.directoryURL = source ? settings.sourceURL : settings.destinationURL
        if panel.runModal() == .OK, let url = panel.url { setFolder(url, source: source) }
    }
    func setFolder(_ url: URL, source: Bool) {
        guard !busy else { return }
        if source { settings.sourceURL = url; if settings.destinationURL == nil { settings.destinationURL = url } }
        else { settings.destinationURL = url }
        invalidatePlan()
    }
    func addExclusion() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { settings.scanOptions.excludedURLs.append(contentsOf: panel.urls) }
    }
    func preview() async {
        guard canPreview, let source = settings.sourceURL, let destination = settings.destinationURL else { return }
        busy = true; message = nil; lastSummary = nil; plan = nil; processed = 0; total = 0; currentFile = ""
        let rules = settings.rules, options = settings.scanOptions, protectedRoot = dataRoot
        let scan = Task { try await ScanPlanner.plan(source: source, destination: destination, rules: rules, options: options, now: .now, protectedURLs: [protectedRoot]) }
        previewTask = scan
        defer { previewTask = nil; busy = false }
        do { let result = try await scan.value; try Task.checkCancellation(); plan = result }
        catch is CancellationError { plan = nil; message = tr("Preview cancelled", "Предпросмотр отменён") }
        catch { message = error.localizedDescription }
    }
    func sort() async {
        guard canSort, let p = plan, let coordinator else { return }
        busy = true; message = nil; defer { busy = false; plan = nil }
        if settings.hideOtherApps { NSApp.hideOtherApplications(nil) }
        do {
            lastSummary = try await coordinator.execute(plan: p); lastTidyID = p.id
            await refreshHistory()
            if settings.revealAfterRun { NSWorkspace.shared.open(p.destinationRoot) }
            await logSummary()
        } catch { message = error.localizedDescription; await refreshHistory() }
    }
    func cancel() async { previewTask?.cancel(); await coordinator?.cancel() }
    func undo(runID: UUID) async {
        guard !busy, startupError == nil, let coordinator else { return }
        busy = true; message = nil; defer { busy = false; plan = nil }
        do { lastSummary = try await coordinator.undo(runID: runID); lastTidyID = nil; await refreshHistory(); await logSummary() }
        catch { message = error.localizedDescription }
    }
    func refreshHistory() async {
        do { if let journal { history = try await journal.runs().filter { $0.undoOfRun == nil } } } catch { message = error.localizedDescription }
    }
    func records(_ id: UUID) async -> [OperationRecord] {
        do { return try await journal?.operations(runID: id) ?? [] } catch { message = error.localizedDescription; return [] }
    }
    private func logSummary() async {
        guard settings.diagnosticLogging, let summary = lastSummary else { return }
        let root = dataRoot, text = "\(Date().ISO8601Format()) \(summary)\n"
        do {
            try await Task.detached {
                let url = root.appendingPathComponent("diagnostic.log")
                if !PathSafety.exists(url) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
                let file = try FileHandle(forWritingTo: url); defer { try? file.close() }; try file.seekToEnd(); try file.write(contentsOf: Data(text.utf8))
            }.value
        } catch { message = error.localizedDescription }
    }
    func ruleName(_ rule: Rule) -> String {
        guard rule.builtin, russian else { return rule.name }
        let labels = ["3D Models":"3D-модели", "Audio":"Аудио", "Bookmarks":"Закладки", "Developer Files":"Файлы разработки", "Disk Images":"Образы дисков", "eBooks":"Электронные книги", "Emails":"Письма", "Fonts":"Шрифты", "Images":"Изображения", "Markdown":"Markdown", "Movies":"Видео", "PDFs":"PDF", "PowerPoint":"PowerPoint", "Presentations":"Презентации", "Scripts":"Скрипты", "Source Code":"Исходный код", "Spreadsheets":"Таблицы", "Text Files":"Текстовые файлы", "Unknown":"Другие файлы", "Word Processing":"Документы", "Zip & Archives":"Архивы", "Folders":"Папки", "Aliases":"Псевдонимы"]
        return labels[rule.name] ?? rule.name
    }
    func status(_ text: String) -> String { tr(text.capitalized, ["running":"Прервано", "completed":"Готово", "partial":"Частично", "cancelled":"Отменено", "restored":"Восстановлено", "prepared":"Ожидает", "copying":"Копирование", "verified":"Проверено", "publishIntent":"Перемещение", "committed":"Перемещено", "deleteIntent":"Завершение", "sourceRemoved":"Завершение", "conflict":"Конфликт", "failed":"Ошибка"][text] ?? text) }
}
