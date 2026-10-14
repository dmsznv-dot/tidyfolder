import SwiftUI
import AppKit
import TidyCore
struct HistoryView: View {
    let model: AppModel
    @State private var detail: RunRecord?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 8) { Text(model.tr("Every move, remembered.", "Каждое перемещение сохранено.")).font(.system(size: 29, weight: .semibold)); Text(model.tr("Restore a sort even after restarting the app.", "Отменяйте сортировку даже после перезапуска приложения.")).foregroundStyle(.secondary) }; Spacer(); Button { Task { await model.refreshHistory() } } label: { Image(systemName: "arrow.clockwise") }.help(model.tr("Refresh", "Обновить")) }.padding(28)
            if model.history.isEmpty { ContentUnavailableView(model.tr("No sorts yet", "История пока пуста"), systemImage: "clock", description: Text(model.tr("Completed and interrupted sorts appear here.", "Здесь появятся завершённые и прерванные сортировки."))).frame(maxHeight: .infinity) }
            else { List(model.history) { run in
                HStack(spacing: 14) { Image(systemName: run.status == "restored" ? "arrow.uturn.backward.circle" : "folder").font(.title2).foregroundStyle(.tint); VStack(alignment: .leading, spacing: 5) { Text(run.plan.sourceRoot.lastPathComponent).fontWeight(.semibold); Text(run.plan.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(model.status(run.status)).font(.caption).foregroundStyle(.secondary); Button(model.tr("Details", "Подробнее")) { detail = run }; Button(model.tr("Restore", "Восстановить")) { Task { await model.undo(runID: run.id) } }.disabled(model.busy || run.status == "restored") }.padding(.vertical, 10)
            } }
        }.sheet(item: $detail) { run in RunDetails(run: run, model: model) }
    }
}
private struct RunDetails: View {
    let run: RunRecord
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var operations: [OperationRecord] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(run.plan.sourceRoot.lastPathComponent).font(.title2).fontWeight(.semibold); Spacer(); Text(model.status(run.status)).foregroundStyle(.secondary) }
            Text(run.plan.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
            Table(operations) { TableColumn(model.tr("File", "Файл")) { Text($0.operation.source.url.lastPathComponent) }; TableColumn(model.tr("Destination", "Назначение")) { Text($0.operation.destination.path).lineLimit(1).truncationMode(.middle) }; TableColumn(model.tr("Status", "Статус")) { Text(model.status($0.state.rawValue)) }.width(110) }.frame(height: 280)
            if let summary = run.summary {
                Text(model.tr("Moved: \(summary.moved) · Copied: \(summary.copied) · Sources kept: \(summary.sourceRetained)", "Перемещено: \(summary.moved) · Скопировано: \(summary.copied) · Источников сохранено: \(summary.sourceRetained)")).font(.caption).foregroundStyle(.secondary)
            }
            if let summary = run.summary, !summary.issues.isEmpty { ScrollView { Text(summary.issues.joined(separator: "\n")).font(.caption).textSelection(.enabled) }.frame(maxHeight: 80) }
            HStack { Button(model.tr("Show in Finder", "Показать в Finder")) { NSWorkspace.shared.open(run.plan.destinationRoot) }; Spacer(); Button(model.tr("Close", "Закрыть")) { dismiss() }.keyboardShortcut(.cancelAction); Button(model.tr("Restore files", "Восстановить файлы")) { dismiss(); Task { await model.undo(runID: run.id) } }.buttonStyle(.borderedProminent).disabled(model.busy || run.status == "restored") }
        }.padding(24).frame(width: 780).task { operations = await model.records(run.id) }
    }
}
