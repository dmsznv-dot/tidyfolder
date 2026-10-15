import SwiftUI
import TidyCore
struct SortView: View {
    @Bindable var model: AppModel
    @State private var optionsExpanded = false
    var body: some View {
        // Bound the expandable header so its intrinsic height cannot overflow the window.
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) { Text(model.tr("A place for every file.", "Каждому файлу — своё место.")).font(.system(size: 29, weight: .semibold)); Text(model.tr("Choose a folder, review the plan, and bring a little order.", "Выберите папку, проверьте план и наведите порядок.")).foregroundStyle(.secondary) }
                    Spacer(); Label(model.tr("On your Mac", "На вашем Mac"), systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                HStack(spacing: 14) {
                    FolderCard(title: model.tr("Source", "Источник"), url: model.settings.sourceURL, empty: model.tr("Choose a folder", "Выберите папку"), button: model.tr("Choose…", "Выбрать…"), choose: { model.choose(source: true) }, drop: { model.setFolder($0, source: true) })
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    FolderCard(title: model.tr("Destination", "Назначение"), url: model.settings.destinationURL, empty: model.tr("Where files go", "Куда сложить файлы"), button: model.tr("Choose…", "Выбрать…"), choose: { model.choose(source: false) }, drop: { model.setFolder($0, source: false) })
                }.disabled(model.busy)
                HStack { Toggle(model.tr("Include subfolders", "Включить подпапки"), isOn: $model.settings.scanOptions.recursive).toggleStyle(.checkbox); Spacer(); Button(model.tr("Use source as destination", "Сортировать в исходной папке")) { model.settings.destinationURL = model.settings.sourceURL }.buttonStyle(.link).disabled(model.settings.sourceURL == nil) }.disabled(model.busy)
                DisclosureGroup(model.tr("Options & exclusions", "Настройки и исключения"), isExpanded: $optionsExpanded) { ScanOptionsView(model: model).padding(.top, 12) }.font(.callout).disabled(model.busy)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: min(optionsExpanded ? 520 : 360, geometry.size.height * (optionsExpanded ? 0.78 : 0.62)))
            Divider()
            if model.busy {
                VStack(spacing: 12) { ProgressView(value: Double(model.processed), total: Double(max(1, model.total))); Text(model.currentFile.isEmpty ? model.tr("Working…", "Обработка…") : model.currentFile).font(.caption).foregroundStyle(.secondary); Button(model.tr("Cancel", "Отменить")) { Task { await model.cancel() } } }.padding(30).frame(maxHeight: .infinity)
            } else if let plan = model.plan { PreviewView(plan: plan, model: model) }
            else if let result = model.lastSummary {
                VStack(spacing: 14) { Image(systemName: result.failed == 0 && result.sourceRetained == 0 && !result.cancelled ? "checkmark.circle" : "exclamationmark.circle").font(.system(size: 46)).foregroundStyle(result.failed == 0 && result.sourceRetained == 0 && !result.cancelled ? .green : .orange); Text(result.cancelled ? model.tr("Stopped safely", "Операция остановлена") : result.failed > 0 || result.sourceRetained > 0 ? model.tr("Partially completed", "Завершено частично") : model.tr("All done.", "Готово.")).font(.title2).fontWeight(.semibold); Text(model.tr("Processed: \(result.moved) · Copied: \(result.copied) · Sources kept: \(result.sourceRetained) · Skipped: \(result.skipped) · Issues: \(result.failed)", "Обработано: \(result.moved) · Скопировано: \(result.copied) · Источников сохранено: \(result.sourceRetained) · Пропущено: \(result.skipped) · Ошибок: \(result.failed)")).foregroundStyle(.secondary); if let id = model.lastTidyID { Button(model.tr("Undo this sort", "Отменить сортировку")) { Task { await model.undo(runID: id) } } }; if !result.issues.isEmpty { ScrollView { Text(result.issues.joined(separator: "\n")).font(.caption).textSelection(.enabled) }.frame(maxHeight: 80) } }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) { Image(systemName: "tray.2").font(.system(size: 36)).foregroundStyle(.tertiary); Text(model.tr("See the plan before anything moves.", "Сначала проверьте план перемещений.")).font(.headline).foregroundStyle(.secondary); Text(model.tr("Your rules decide where files belong.", "Правила определяют, в какую папку попадёт файл.")).font(.callout).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack { Button { model.section = .rules } label: { Label(model.tr("\(model.settings.rules.filter(\.enabled).count) active rules", "Активных правил: \(model.settings.rules.filter(\.enabled).count)"), systemImage: "slider.horizontal.3") }.buttonStyle(.plain).foregroundStyle(.secondary); Spacer(); Button(model.tr("Preview", "Предпросмотр")) { Task { await model.preview() } }.disabled(!model.canPreview); Button(model.tr("Organize", "Сортировать")) { Task { await model.sort() } }.buttonStyle(.borderedProminent).disabled(!model.canSort).keyboardShortcut(.defaultAction) }.padding(18)
        }.background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct ScanOptionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Toggle(model.tr("Include empty folders", "Включить пустые папки"), isOn: $model.settings.scanOptions.emptyFolders); Spacer(); Toggle(model.tr("Remove empty source folders", "Удалять пустые папки источника"), isOn: $model.settings.scanOptions.removeEmptyFolders) }
            Toggle(model.tr("Keep application and document packages intact", "Сохранять целостность пакетов приложений и документов"), isOn: $model.settings.scanOptions.skipBundles)
            Toggle(model.tr("Create a dated top-level folder", "Создавать папку с датой сортировки"), isOn: $model.settings.scanOptions.datedRoot)
            HStack {
                Picker(model.tr("Name conflicts", "Совпадение имён"), selection: $model.settings.scanOptions.conflictPolicy) { Text(model.tr("Skip", "Пропустить")).tag(ScanOptions.ConflictPolicy.skip); Text(model.tr("Keep both", "Сохранить оба")).tag(ScanOptions.ConflictPolicy.keepBoth) }
                Picker(model.tr("Finder tags", "Теги Finder"), selection: $model.settings.scanOptions.taggedPolicy) { Text(model.tr("Include all", "Все файлы")).tag(ScanOptions.TaggedPolicy.includeAll); Text(model.tr("Skip tagged", "Без тегов")).tag(ScanOptions.TaggedPolicy.skipTagged); Text(model.tr("Only tagged", "Только с тегами")).tag(ScanOptions.TaggedPolicy.onlyTagged) }
            }
            HStack { Text(model.tr("Excluded items", "Исключения")).foregroundStyle(.secondary); Spacer(); Button(model.tr("Add…", "Добавить…")) { model.addExclusion() } }
            ForEach(model.settings.scanOptions.excludedURLs, id: \.absoluteString) { url in HStack { Text(url.path).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button { model.settings.scanOptions.excludedURLs.removeAll { $0 == url } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) } }
        }.toggleStyle(.checkbox)
    }
}

struct PreviewView: View {
    let plan: TidyPlan
    let model: AppModel
    @State private var showingSkipped = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(model.tr("\(plan.operations.count) files ready to organize", "Файлов к сортировке: \(plan.operations.count)")).font(.headline); Spacer(); if !plan.skips.isEmpty { Toggle(model.tr("Skipped: \(plan.skips.count)", "Пропущено: \(plan.skips.count)"), isOn: $showingSkipped).toggleStyle(.button) } }.padding(16)
            if showingSkipped { Table(plan.skips) { TableColumn(model.tr("File", "Файл")) { Text($0.url.lastPathComponent) }; TableColumn(model.tr("Reason", "Причина"), value: \.reason) } }
            else { Table(plan.operations) { TableColumn(model.tr("File", "Файл")) { Label($0.source.url.lastPathComponent, systemImage: "doc") }; TableColumn(model.tr("Destination", "Назначение")) { Text($0.destination.path).lineLimit(1).truncationMode(.middle) }; TableColumn(model.tr("Size", "Размер")) { Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: $0.source.metadata.size), countStyle: .file)).foregroundStyle(.secondary) }.width(80) } }
        }
    }
}
