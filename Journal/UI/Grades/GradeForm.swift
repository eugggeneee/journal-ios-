import SwiftUI

private let gradeKinds = ["Ответ", "Контрольная", "Лабораторная", "Практическая", "Самостоятельная", "Тест", "Зачёт", "Экзамен"]

/// Добавление и правка оценки.
struct GradeForm: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    let edit: Grade?
    let close: () -> Void

    @State private var subject: String
    @State private var value: Int?
    @State private var date: Date
    @State private var kind: String
    @State private var note: String
    @State private var added = 0
    @State private var confirmDelete = false

    init(edit: Grade?, subject: String?, date: Date?, close: @escaping () -> Void) {
        self.edit = edit
        self.close = close
        _subject = State(initialValue: edit?.subject ?? subject ?? "")
        _value = State(initialValue: edit?.value)
        _date = State(initialValue: edit?.date ?? date ?? today())
        _kind = State(initialValue: edit?.kind ?? "")
        _note = State(initialValue: edit?.note ?? "")
    }

    private var editing: Bool { edit != nil }
    private var canSave: Bool { !subject.isEmpty && value != nil }

    private var suggested: [String] {
        guard let s = store.cachedSchedule(on: date) else { return [] }
        return s.slots.flatMap { $0.subjects }
    }

    private var hint: String? {
        if canSave { return nil }
        if subject.isEmpty && value == nil { return "Выберите оценку и предмет" }
        return subject.isEmpty ? "Выберите предмет" : "Выберите оценку"
    }

    var body: some View {
        Form {
            Section {
                preview
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("Оценка") {
                GradePad(value: $value)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }

            Section {
                SubjectField(subject: $subject, suggested: suggested)
                Picker(selection: $kind) {
                    Text("Не указан").tag("")
                    ForEach(gradeKinds, id: \.self) { Text($0).tag($0) }
                    if !kind.isEmpty && !gradeKinds.contains(kind) { Text(kind).tag(kind) }
                } label: {
                    Label("Тип работы", systemImage: "doc.text")
                }
                DatePicker(selection: $date, displayedComponents: .date) {
                    Label("Дата", systemImage: "calendar")
                }
            } footer: {
                if let hint = hint { Text(hint) }
            }

            Section("Заметка") {
                TextField("Например, ответ у доски", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            if !editing {
                Section {
                    Button {
                        commit(another: true)
                    } label: {
                        Label("Сохранить и добавить ещё", systemImage: "plus.square.on.square")
                    }
                    .disabled(!canSave)
                }
            } else {
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Удалить оценку", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(editing ? "Изменить оценку" : (added > 0 ? "Добавлено: \(added)" : "Новая оценка"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { close() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { commit(another: false) }
                    .disabled(!canSave)
            }
        }
        .confirmationDialog("Удалить оценку?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Предпросмотр

    private var preview: some View {
        let v = value
        let color: Color = v.map { gradeFill($0) } ?? Color(.systemGray)
        let details = ([dayCaption(date)] + (kind.isEmpty ? [] : [kind])).joined(separator: " · ")
        return HStack(spacing: 16) {
            Text(v.map { "\($0)" } ?? "–")
                .font(.system(size: v == 10 ? 34 : 40, weight: .bold, design: .rounded))
                .foregroundStyle(v.map { gradeText($0) } ?? Color.secondary)
                .contentTransition(.numericText())
                .frame(width: 80, height: 80)
                .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(subject.isEmpty ? "Предмет не выбран" : store.subjectName(subject))
                    .font(.headline)
                    .lineLimit(2)
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.smooth, value: value)
        .padding(.horizontal, 4)
    }

    // MARK: Действия

    private func commit(another: Bool) {
        guard canSave, let v = value else { return }
        let store = self.store
        let old = edit
        let g = Grade(id: old?.id ?? newId(), subject: subject, value: v, date: date, kind: kind,
                      note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        store.saveGrade(g)
        Haptics.success()
        let what = "\(g.value) · \(store.subjectName(g.subject))"
        if another {
            value = nil
            note = ""
            added += 1
            toaster.show("Добавлено: \(what)")
            return
        }
        close()
        toaster.show(old == nil ? "Оценка добавлена: \(what)" : "Оценка изменена: \(what)") {
            if let old = old { store.saveGrade(old) } else { store.deleteGrade(g.id) }
        }
    }

    private func delete() {
        guard let g = edit else { return }
        let store = self.store
        store.deleteGrade(g.id)
        Haptics.medium()
        close()
        toaster.show("Оценка удалена") { store.saveGrade(g) }
    }
}

/// Клавиатура оценок 1–10.
struct GradePad: View {
    @Binding var value: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...10, id: \.self) { n in
                let selected = value == n
                Button {
                    Haptics.selection()
                    value = n
                } label: {
                    Text("\(n)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? Color.white : gradeText(n))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(selected ? gradeFill(n) : gradeFill(n).opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Оценка \(n)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
