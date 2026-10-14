import SwiftUI
import TidyCore
struct MainView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.section) {
                    Label(model.tr("Organize", "Сортировка"), systemImage: "folder.badge.gearshape").tag(AppModel.Section.sort)
                    Label(model.tr("Rules", "Правила"), systemImage: "line.3.horizontal.decrease.circle").tag(AppModel.Section.rules)
                    Label(model.tr("History", "История"), systemImage: "clock.arrow.circlepath").tag(AppModel.Section.history)
                }.listStyle(.sidebar)
                HStack(spacing: 8) { Image(systemName: "folder.fill").foregroundStyle(.tint); VStack(alignment: .leading, spacing: 2) { Text("TidyFolder").fontWeight(.semibold); Text("0.1.0").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(16)
            }.navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 250)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.startupError ?? model.message { HStack(alignment: .top) { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange); Text(error).textSelection(.enabled); Spacer(); if model.startupError == nil { Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) } }.padding(12).background(.orange.opacity(0.09)) }
                switch model.section { case .sort: SortView(model: model); case .rules: RulesView(model: model); case .history: HistoryView(model: model) }
            }
        }
        .navigationTitle("TidyFolder")
        .toolbar { ToolbarItem { SettingsLink { Image(systemName: "gearshape") }.help(model.tr("Settings", "Настройки")) } }
        .task { await model.bootstrap() }
        .onChange(of: model.settings) { _, _ in model.preferencesChanged() }
    }
}

struct FolderCard: View {
    let title: String
    let url: URL?
    let empty: String
    let button: String
    let choose: () -> Void
    let drop: (URL) -> Void
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
            HStack(spacing: 13) { Image(systemName: "folder.fill").font(.system(size: 34)).foregroundStyle(.tint); VStack(alignment: .leading, spacing: 5) { Text(url?.lastPathComponent ?? empty).font(.headline).lineLimit(1); Text(url?.path ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) } }
            Button(button, action: choose).buttonStyle(.bordered)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: targeted ? 2 : 1))
        .dropDestination(for: URL.self) { urls, _ in guard let url = urls.first, (try? SnapshotReader.read(url).isDirectory) == true else { return false }; drop(url); return true } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
    }
}
