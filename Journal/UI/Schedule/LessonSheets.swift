import SwiftUI

private let customMarkChoice = "__custom__"
private let markMaxLength = 24

// MARK: - Пометка

/// Пометка к дню или к паре: «ОКР», «Зачёт», «Практика», «Сокращённый день» или своя.
struct MarkForm: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    let edit: DayMark?
    let close: () -> Void

    @State private var date: Date
    @State private var lesson: Int
    @State private var choice: String
    @State private var custom: String
    @State private var confirmDelete = false

    init(edit: DayMark?, date: Date, lesson: Int?, close: @escaping () -> Void) {
        self.edit = edit
        self.close = close
        _date = State(initialValue: edit?.date ?? date)
        _lesson = State(initialValue: edit?.lesson ?? lesson ?? 0)
        if let e = edit, !kMarkPresets.contains(e.label) {
            _choice = State(initialValue: customMarkChoice)
            _custom = State(initialValue: e.label)
        } else {
            _choice = State(initialValue: edit?.label ?? kMarkPresets[0])
            _custom = State(initialValue: "")
        }
    }

    private var label: String {
        choice == customMarkChoice ? custom.trimmingCharacters(in: .whitespacesAndNewlines) : choice
    }

    private var slots: [LessonSlot] { store.cachedSchedule(on: date)?.slots ?? [] }

    private var existing: DayMark? { store.mark(on: date, lesson: lesson) }

    var body: some View {
        Form {
            Section {
                DatePicker(selection: $date, displayedComponents: .date) {
                    Label("Дата", systemImage: "calendar")
                }
            }

            Section("Что это") {
                ForEach(kMarkPresets, id: \.self) { p in
                    optionRow(title: p, selected: choice == p) {
                        choice = p
                        if p == kShortDayMark { lesson = 0 }
                    }
                }
                optionRow(title: "Своя пометка", selected: choice == customMarkChoice) { choice = customMarkChoice }
                if choice == customMarkChoice {
                    TextField("Например, консультация", text: $custom)
                        .onChange(of: custom) { _, v in
                            if v.count > markMaxLength { custom = String(v.prefix(markMaxLength)) }
                        }
                }
            }

            Section {
                Picker(selection: $lesson) {
                    Text("Весь день").tag(0)
                    ForEach(1...kMaxPairs, id: \.self) { n in
                        Text(pairLabel(n)).tag(n)
                    }
                } label: {
                    Label("К чему относится", systemImage: "scope")
                }
            } footer: {
                if let e = existing, e.id != edit?.id {
                    Text("Прежняя пометка «\(e.label)» будет заменена.")
                }
            }

            if edit != nil {
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Удалить пометку", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(edit == nil ? "Новая пометка" : "Изменить пометку")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }.disabled(label.isEmpty)
            }
        }
        .confirmationDialog("Удалить пометку?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func pairLabel(_ n: Int) -> String {
        if let s = slots.first(where: { $0.number == n }) { return "\(n) пара · \(store.subjectName(s.subject))" }
        return "\(n) пара"
    }

    private func optionRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
    }

    private func save() {
        guard !label.isEmpty else { return }
        let store = self.store
        let date = self.date
        let before = store.snapshotMarks(date)
        let oldDate = edit?.date
        let beforeOld: [DayMark]? = {
            guard let e = edit, !sameDay(e.date, date) else { return nil }
            return store.snapshotMarks(e.date)
        }()
        let id = edit?.id ?? existing?.id ?? newId()
        store.saveMark(DayMark(id: id, date: date, lesson: lesson, label: label))
        Haptics.success()
        close()
        toaster.show(edit == nil ? "Пометка добавлена" : "Пометка изменена") {
            store.restoreMarks(date, before)
            if let b = beforeOld, let od = oldDate { store.restoreMarks(od, b) }
        }
    }

    private func delete() {
        guard let m = edit else { return }
        let store = self.store
        let before = store.snapshotMarks(m.date)
        store.deleteMark(m.id)
        Haptics.medium()
        close()
        toaster.show("Пометка удалена") { store.restoreMarks(m.date, before) }
    }
}

// MARK: - Пара

/// Подробности пары: время, аудитория, преподаватель, пропуск, пометка и оценка.
struct LessonSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    let date: Date
    let slot: LessonSlot
    let close: () -> Void

    @State private var subjectPick: String?
    @State private var hours: Int?

    private var absence: Absence? { store.absence(on: date, lesson: slot.number) }
    private var dayMark: DayMark? { store.mark(on: date, lesson: slot.number) }
    private var bell: BellSlot? { store.bell(on: date, lesson: slot.number) }
    private var currentSubject: String { subjectPick ?? absence?.subject ?? slot.subject }
    private var currentHours: Int { hours ?? absence?.hours ?? store.settings.absenceHours }

    var body: some View {
        Form {
            Section {
                if let bell = bell {
                    LabeledContent {
                        Text("\(slotRange(bell))")
                    } label: {
                        Label("Время", systemImage: "clock")
                    }
                    if bell.hasBreak {
                        LabeledContent {
                            Text("\(halvesText(bell)) · \(innerBreakWord(bell)) \(minText(bell.breakMinutes))")
                        } label: {
                            Label("Состав", systemImage: "rectangle.split.2x1")
                        }
                    }
                }
                ForEach(Array(slot.entries.enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 4) {
                        if slot.entries.count > 1 {
                            Text(store.subjectName(e.subject)).font(.subheadline.weight(.semibold))
                        }
                        if !e.room.isEmpty { Label("Аудитория \(e.room)", systemImage: "door.left.hand.open") }
                        if !e.teacher.isEmpty { Label(e.teacher, systemImage: "person") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            if slot.subjects.count > 1 {
                Section("Предмет для пропуска") {
                    Picker("Предмет", selection: Binding(get: { currentSubject }, set: { newValue in
                        subjectPick = newValue
                        if let a = absence { writeAbsence(excused: a.excused, subject: newValue, quiet: true) }
                    })) {
                        ForEach(slot.subjects, id: \.self) { Text(store.subjectName($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            Section {
                HoursPicker(hours: Binding(get: { currentHours }, set: { hours = $0 })) { h in
                    if let a = absence { writeAbsence(excused: a.excused, hours: h, quiet: true) }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                ExcuseButtons(selected: absence?.excused) { writeAbsence(excused: $0) }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                if let a = absence {
                    NavigationLink {
                        AbsenceForm(edit: a, date: nil, lesson: nil, subject: nil, hours: a.hours, close: close)
                    } label: {
                        Label("Подробнее о пропуске", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) { removeAbsence(a) } label: {
                        Label("Снять пропуск", systemImage: "xmark.circle")
                    }
                }
            } header: {
                Text("Пропуск")
            } footer: {
                if absence == nil { Text("Выберите причину — пропуск сохранится сразу.") }
            }

            Section("Пометка") {
                NavigationLink {
                    MarkForm(edit: dayMark, date: date, lesson: slot.number, close: close)
                } label: {
                    if let m = dayMark {
                        Label(m.label, systemImage: "flag.fill").foregroundStyle(markColor)
                    } else {
                        Label("Добавить пометку", systemImage: "flag")
                    }
                }
            }

            Section {
                NavigationLink {
                    GradeForm(edit: nil, subject: currentSubject, date: date, close: close)
                } label: {
                    Label("Добавить оценку", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(slot.subjects.map(store.subjectName).joined(separator: " / "))
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle("\(slot.number) пара · \(dayCaption(date))")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Готово") { close() } }
        }
    }

    private func writeAbsence(excused: Bool, subject: String? = nil, hours h: Int? = nil, quiet: Bool = false) {
        let store = self.store
        let before = store.snapshotDay(date)
        let old = absence
        let a = Absence(id: old?.id ?? newId(), date: date, lesson: slot.number,
                        subject: subject ?? currentSubject, hours: h ?? currentHours,
                        excused: excused, note: old?.note ?? "")
        store.saveAbsence(a)
        Haptics.success()
        if quiet { return }
        let kind = excused ? "по уважительной" : "без уважительной"
        let date = self.date
        toaster.show("\(slot.number) пара — \(hoursText(a.hours)) · \(kind)") { store.restoreDay(date, before) }
    }

    private func removeAbsence(_ a: Absence) {
        let store = self.store
        let date = self.date
        let before = store.snapshotDay(date)
        store.deleteAbsence(a.id)
        Haptics.light()
        toaster.show("\(slot.number) пара — пропуск снят") { store.restoreDay(date, before) }
    }
}
