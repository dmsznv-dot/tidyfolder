import SwiftUI
import TidyCore
private struct GroupDraft {
    var mode: RuleGroup.Mode
    var nodes: [NodeDraft]
    init(_ group: RuleGroup = .init()) { mode = group.mode; nodes = group.children.map(NodeDraft.init) }
    var domain: RuleGroup { .init(mode: mode, children: nodes.map { $0.group.map { .group($0.domain) } ?? .condition($0.condition) }) }
}
private struct NodeDraft: Identifiable {
    var id = UUID()
    var condition = RuleCondition()
    var group: GroupDraft?
    init(_ node: RuleNode) { switch node { case .condition(let c): condition = c; case .group(let g): group = GroupDraft(g) } }
}
struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: Rule
    @State private var group: GroupDraft
    let model: AppModel
    let save: (Rule) -> Void
    init(rule: Rule, model: AppModel, save: @escaping (Rule) -> Void) { _rule = State(initialValue: rule); _group = State(initialValue: GroupDraft(rule.group)); self.model = model; self.save = save }
    var valid: Bool { !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && RuleEngine.valid(group.domain) && (try? PathSafety.validateRelative(rule.destination)) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.tr("Custom rule", "Пользовательское правило")).font(.title2).fontWeight(.semibold)
            Form { TextField(model.tr("Name", "Название"), text: $rule.name); TextField(model.tr("Destination folder", "Папка назначения"), text: $rule.destination) }
            Text(model.tr("Relative to the destination. Example: Work/Invoices", "Внутри папки назначения. Например: Работа/Счета")).font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView { DraftGroupView(group: $group, model: model, depth: 0) }.frame(minHeight: 150, maxHeight: 400)
            if !valid { Text(model.tr("Add a valid condition and destination folder to save.", "Укажите папку назначения и заполните условия.")).font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button(model.tr("Cancel", "Отмена")) { dismiss() }.keyboardShortcut(.cancelAction); Button(model.tr("Save rule", "Сохранить")) { rule.group = group.domain; save(rule); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!valid) }
        }.padding(28).frame(width: 710)
    }
}
private struct DraftGroupView: View {
    @Binding var group: GroupDraft
    let model: AppModel
    let depth: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Picker(model.tr("Match", "Совпадают"), selection: $group.mode) { Text(model.tr("All conditions", "Все условия")).tag(RuleGroup.Mode.all); Text(model.tr("Any condition", "Любое условие")).tag(RuleGroup.Mode.any); Text(model.tr("None of the conditions", "Ни одно условие")).tag(RuleGroup.Mode.none) }.fixedSize(); Spacer() }
            ForEach($group.nodes) { $node in
                HStack(alignment: .top) {
                    if node.group != nil { AnyView(DraftGroupView(group: Binding(get: { node.group ?? GroupDraft() }, set: { node.group = $0 }), model: model, depth: depth + 1).padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))) }
                    else { ConditionRow(condition: $node.condition, model: model) }
                    Button { group.nodes.removeAll { $0.id == node.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help(model.tr("Remove condition", "Удалить условие"))
                }
            }
            HStack { Button(model.tr("Add condition", "Добавить условие")) { group.nodes.append(NodeDraft(.condition(.init()))) }; if depth < 7 { Button(model.tr("Add group", "Добавить группу")) { group.nodes.append(NodeDraft(.group(.init(children: [.condition(.init())])))) } } }.font(.callout)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct ConditionRow: View {
    @Binding var condition: RuleCondition
    let model: AppModel
    var comparisons: [RuleCondition.Comparison] {
        switch condition.field { case .size: [.equals,.notEquals,.greaterThan,.lessThan,.atLeast,.atMost]; case .createdAt,.modifiedAt: [.withinDays,.olderThanDays,.greaterThan,.lessThan,.atLeast,.atMost,.equals]; default: [.equals,.notEquals,.contains,.notContains,.beginsWith,.endsWith] }
    }
    func field(_ f: RuleCondition.Field) -> String { model.tr([.name:"Name",.fileExtension:"Extension",.type:"File type",.kind:"Item kind",.size:"Size (bytes)",.createdAt:"Created",.modifiedAt:"Modified",.tags:"Finder tag"][f] ?? f.rawValue, [.name:"Имя",.fileExtension:"Расширение",.type:"Тип файла",.kind:"Тип объекта",.size:"Размер (байт)",.createdAt:"Создан",.modifiedAt:"Изменён",.tags:"Тег Finder"][f] ?? f.rawValue) }
    func comparison(_ c: RuleCondition.Comparison) -> String { model.tr([.equals:"is",.notEquals:"is not",.contains:"contains",.notContains:"does not contain",.beginsWith:"begins with",.endsWith:"ends with",.greaterThan:"greater than",.lessThan:"less than",.atLeast:"at least",.atMost:"at most",.withinDays:"within days",.olderThanDays:"older than days"][c] ?? c.rawValue, [.equals:"равно",.notEquals:"не равно",.contains:"содержит",.notContains:"не содержит",.beginsWith:"начинается с",.endsWith:"заканчивается на",.greaterThan:"больше",.lessThan:"меньше",.atLeast:"не меньше",.atMost:"не больше",.withinDays:"за последние дни",.olderThanDays:"старше дней"][c] ?? c.rawValue) }
    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $condition.field) { ForEach(RuleCondition.Field.allCases, id: \.self) { Text(field($0)).tag($0) } }.labelsHidden().frame(width: 140).accessibilityLabel(model.tr("File property", "Свойство файла"))
            Picker("", selection: $condition.comparison) { ForEach(comparisons, id: \.self) { Text(comparison($0)).tag($0) } }.labelsHidden().frame(width: 150).accessibilityLabel(model.tr("Comparison", "Сравнение"))
            if condition.field == .type {
                Picker("", selection: $condition.value) { Text(model.tr("Images", "Изображения")).tag("public.image"); Text(model.tr("Movies", "Видео")).tag("public.movie"); Text(model.tr("Audio", "Аудио")).tag("public.audio"); Text("PDF").tag("com.adobe.pdf"); Text(model.tr("Text", "Текст")).tag("public.text"); Text(model.tr("Archives", "Архивы")).tag("public.archive") }.labelsHidden()
            } else if condition.field == .kind {
                Picker("", selection: $condition.value) { Text(model.tr("File", "Файл")).tag("regularFile"); Text(model.tr("Folder", "Папка")).tag("directory"); Text(model.tr("Package", "Пакет")).tag("package"); Text(model.tr("Finder alias", "Псевдоним Finder")).tag("alias") }.labelsHidden()
            } else { TextField(condition.field == .size ? "1048576" : condition.field == .modifiedAt || condition.field == .createdAt ? "14 / ISO 8601" : model.tr("Value", "Значение"), text: $condition.value).textFieldStyle(.roundedBorder) }
        }
        .onChange(of: condition.field) { _, field in
            switch field { case .type: condition.comparison = .equals; condition.value = "public.image"; case .kind: condition.comparison = .equals; condition.value = "regularFile"; case .size: condition.comparison = .atLeast; if UInt64(condition.value) == nil { condition.value = "0" }; case .createdAt,.modifiedAt: condition.comparison = .withinDays; condition.value = "14"; default: if !comparisons.contains(condition.comparison) { condition.comparison = .equals } }
        }
    }
}
