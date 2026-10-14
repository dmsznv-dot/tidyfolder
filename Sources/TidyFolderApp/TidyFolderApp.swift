import SwiftUI
@main struct TidyFolderApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("TidyFolder") {
            MainView(model: model).frame(minWidth: 820, minHeight: 560).preferredColorScheme(model.colorScheme).environment(\.locale, Locale(identifier: model.russian ? "ru" : "en"))
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) { Button(model.tr("Choose folder…", "Выбрать папку…")) { model.choose(source: true) }.keyboardShortcut("o").disabled(model.busy) } }
        Settings { SettingsView(model: model).frame(width: 470).preferredColorScheme(model.colorScheme) }
    }
}
