import SwiftUI
import TidyCore
struct RulesView: View {
    @Bindable var model: AppModel
    @State private var selected: UUID?
    @State private var editing: Rule?
    var chosen: Rule? { model.settings.rules.first { $0.id == selected } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) { Text(model.tr("Simple rules. Your order.", "Ваш порядок. Ваши правила.")).font(.system(size: 29, weight: .semibold)); Text(model.tr("The first matching rule wins. Drag to change priority.", "Применяется первое совпавшее правило. Меняйте порядок перетаскиванием.")).foregroundStyle(.secondary) }.padding(28)
            List(selection: $selected) {
                ForEach($model.settings.rules) { $rule in
                    HStack(spacing: 14) {
                        Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox).accessibilityLabel(model.ruleName(rule))
                        Image(systemName: rule.builtin ? "folder" : "slider.horizontal.3").foregroundStyle(.tint).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) { Text(model.ruleName(rule)).fontWeight(.medium); Text(rule.destination).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); if rule.builtin { Image(systemName: "lock").font(.caption).foregroundStyle(.tertiary).help(model.tr("Built-in rule", "Встроенное правило")) }
                    }.padding(.vertical, 7).tag(rule.id).contentShape(Rectangle()).onTapGesture(count: 2) { if !rule.builtin { editing = rule } }
                }.onMove { model.settings.rules.move(fromOffsets: $0, toOffset: $1) }
            }.disabled(model.busy)
            Divider()
            HStack {
                Button { editing = Rule(name: model.tr("New rule", "Новое правило"), destination: "", group: .init(children: [.condition(.init())])) } label: { Label(model.tr("New rule", "Добавить"), systemImage: "plus") }
                Button(model.tr("Edit", "Изменить")) { editing = chosen }.disabled(chosen == nil || chosen?.builtin == true)
                Button { if let selected { model.settings.rules.removeAll { $0.id == selected }; self.selected = nil } } label: { Image(systemName: "minus") }.disabled(chosen == nil || chosen?.builtin == true)
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(selected == nil)
                Button { move(1) } label: { Image(systemName: "arrow.down") }.disabled(selected == nil)
                Spacer()
                Menu(model.tr("Enable…", "Включить…")) { Button(model.tr("All on", "Включить все")) { model.settings.rules = BuiltinRules.settingEnabled(model.settings.rules, enabled: true) }; Button(model.tr("All off", "Выключить все")) { model.settings.rules = BuiltinRules.settingEnabled(model.settings.rules, enabled: false) } }
            }.padding(18).disabled(model.busy)
        }
        .sheet(item: $editing) { rule in RuleEditor(rule: rule, model: model) { saved in
            if let index = model.settings.rules.firstIndex(where: { $0.id == saved.id }) { model.settings.rules[index] = saved }
            else { model.settings.rules.insert(saved, at: 0) }
            editing = nil
        } }
    }
    func move(_ delta: Int) {
        guard let selected, let index = model.settings.rules.firstIndex(where: { $0.id == selected }) else { return }
        let target = index + delta; guard model.settings.rules.indices.contains(target) else { return }
        model.settings.rules.swapAt(index, target)
    }
}
