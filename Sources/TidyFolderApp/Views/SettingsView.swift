import SwiftUI
import TidyCore
struct SettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section(model.tr("Appearance", "Оформление")) {
                Picker(model.tr("Theme", "Тема"), selection: $model.settings.appearance) { Text(model.tr("System", "Системная")).tag(AppSettings.Appearance.system); Text(model.tr("Light", "Светлая")).tag(AppSettings.Appearance.light); Text(model.tr("Dark", "Тёмная")).tag(AppSettings.Appearance.dark) }
                Picker(model.tr("Language", "Язык"), selection: $model.settings.language) { Text(model.tr("System", "Системный")).tag(AppSettings.Language.system); Text("Русский").tag(AppSettings.Language.ru); Text("English").tag(AppSettings.Language.en) }
            }
            Section(model.tr("After organizing", "После сортировки")) { Toggle(model.tr("Show destination in Finder", "Открывать папку назначения в Finder"), isOn: $model.settings.revealAfterRun); Toggle(model.tr("Hide other applications before sorting", "Скрывать другие приложения перед сортировкой"), isOn: $model.settings.hideOtherApps) }
            Section(model.tr("Diagnostics", "Диагностика")) { Toggle(model.tr("Save a local diagnostic log", "Сохранять локальный журнал диагностики"), isOn: $model.settings.diagnosticLogging); Text(model.tr("Files and rules stay on your Mac.", "Файлы и правила хранятся на вашем Mac.")).font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).padding(16).disabled(model.busy).onChange(of: model.settings) { _, _ in model.preferencesChanged() }
    }
}
