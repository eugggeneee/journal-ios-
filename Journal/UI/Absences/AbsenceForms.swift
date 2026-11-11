import SwiftUI

// MARK: - Действия над днём (значок у пары, «Весь день», «Сокращённый день»)

@MainActor
enum DayActions {
    /// Значок пропуска у пары: если пропуска нет — открывается быстрая шторка с выбором причины,
    /// если есть — отметка снимается (с кнопкой «Отменить»).
    static func toggleLessonAbsence(store: AppStore, toaster: Toaster, router: Router, date: Date, slot: LessonSlot) {
        guard let existing = store.absence(on: date, lesson: slot.number) else {
            router.present(.absenceLesson(date: date, slot: slot))
            return
        }
        let before = store.snapshotDay(date)
        store.deleteAbsence(existing.id)
        Haptics.light()
        toaster.show("\(slot.number) пара — пропуск снят") { store.restoreDay(date, before) }
    }

    /// «Весь день»: если не всё отмечено — шторка с выбором причины; если всё — отметки снимаются.
    static func toggleWholeDay(store: AppStore, toaster: Toaster, router: Router, date: Date, slots: [LessonSlot]) {
        guard !slots.isEmpty else { return }
        let allMarked = slots.allSatisfy { store.absence(on: date, lesson: $0.number) != nil }
        if !allMarked {
            router.present(.absenceWholeDay(date: date, slots: slots))
            return
        }
        let before = store.snapshotDay(date)
        store.clearAbsences(on: date, lessons: Set(slots.map { $0.number }))
        Haptics.light()
        toaster.show("Отметки дня сняты") { store.restoreDay(date, before) }
    }

    /// Шаблон пометки на весь день «Сокращённый день»: ставится одним нажатием, повторное — снимает.
    static func toggleShortDay(store: AppStore, toaster: Toaster, date: Date) {
        let before = store.snapshotMarks(date)
        let existing = store.mark(on: date, lesson: 0)
        Haptics.selection()
        if let existing = existing, existing.label == kShortDayMark {
            store.deleteMark(existing.id)
            toaster.show("Пометка снята") { store.restoreMarks(date, before) }
        } else {
            store.saveMark(DayMark(id: existing?.id ?? newId(), date: date, lesson: 0, label: kShortDayMark))
            toaster.show("Сокращённый день отмечен") { store.restoreMarks(date, before) }
        }
    }
}

// MARK: - Быстрая шторка

/// Маленькая шторка: выбрали причину — пропуск сразу сохранён.
struct AbsenceQuickForm: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    /// Если задано — пары уже известны (нажали на пару или «Весь день»), выбор пар скрыт.
    let fixedSlots: [LessonSlot]?
    let wholeDay: Bool
    let close: () -> Void

    @State private var date: Date
    @State private var hours: Int
    @State private var whole = true
    @State private var picked = Set<Int>()
    @State private var manualSubject = ""
    @State private var subjectPick: String?

    init(date: Date, lesson: Int?, fixedSlots: [LessonSlot]?, wholeDay: Bool, hours: Int, close: @escaping () -> Void) {
        self.fixedSlots = fixedSlots
        self.wholeDay = wholeDay
        self.close = close
        _date = State(initialValue: date)
        _hours = State(initialValue: hours)
        if fixedSlots == nil, let n = lesson, n > 0 {
            _whole = State(initialValue: false)
            _picked = State(initialValue: [n])
        }
    }

    private var locked: Bool { fixedSlots != nil }

    private var schedule: DaySchedule? { locked ? nil : store.cachedSchedule(on: date) }

    /// Какие пары будут отмечены. nil — расписания нет, нужен предмет вручную.
    private var slots: [LessonSlot]? {
        if let fixed = fixedSlots { return fixed }
        guard let sched = schedule else { return nil }
        if whole { return sched.slots }
        return sched.slots.filter { picked.contains($0.number) }
    }

    private var canSave: Bool {
        if let slots = slots { return !slots.isEmpty }
        return !manualSubject.isEmpty
    }

    private var single: LessonSlot? {
        if let f = fixedSlots, f.count == 1 { return f[0] }
        return nil
    }

    private func subject(for s: LessonSlot) -> String {
        if let pick = subjectPick, let f = fixedSlots, f.count == 1, s.subjects.contains(pick) { return pick }
        return s.subject
    }

    private var title: String {
        if let single = single { return single.subjects.map(store.subjectName).joined(separator: " / ") }
        if wholeDay { return "Пропуск всего дня" }
        return "Новый пропуск"
    }

    private var subtitle: String? {
        if let single = single { return "\(single.number) пара · \(dayCaption(date))" }
        if wholeDay, let f = fixedSlots { return "\(dayCaption(date)) · \(pairsText(f.count))" }
        return nil
    }

    var body: some View {
        let slotsNow = slots
        let already = slotsNow?.filter { store.absence(on: date, lesson: $0.number) != nil }.count ?? 0
        let totalHours = (slotsNow?.count ?? 1) * hours

        Form {
            if let subtitle = subtitle {
                Section { Text(subtitle).foregroundStyle(.secondary) }
            } else {
                Section {
                    Text("Выберите причину — пропуск сохранится сразу").foregroundStyle(.secondary)
                }
            }

            if !locked {
                Section {
                    DatePicker(selection: $date, displayedComponents: .date) {
                        Label("Дата", systemImage: "calendar")
                    }
                    .onChange(of: date) { _, _ in
                        whole = true
                        picked.removeAll()
                        manualSubject = ""
                    }
                }
                if let sched = schedule {
                    scopeSection(sched)
                } else {
                    Section {
                        SubjectField(subject: $manualSubject)
                    } footer: {
                        Text("На эту дату расписания нет — укажите предмет.")
                    }
                }
            }

            if let single = single, single.subjects.count > 1 {
                Section("Какой предмет?") {
                    Picker("Предмет", selection: Binding(get: { subjectPick ?? single.subject }, set: { subjectPick = $0 })) {
                        ForEach(single.subjects, id: \.self) { Text(store.subjectName($0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            Section {
                HoursPicker(hours: $hours)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } header: {
                Text("Сколько часов")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let s = slotsNow, s.count > 1 { Text("Всего \(hoursText(totalHours))") }
                    if already > 0 {
                        Text(already == 1 ? "Одна из пар уже отмечена — отметка заменится."
                                          : "Часть пар уже отмечена — их отметки заменятся.")
                    }
                }
            }

            if !wholeDay {
                Section {
                    NavigationLink {
                        detailsForm
                    } label: {
                        Label("Подробнее: пара, предмет, заметка", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExcuseButtons(selected: nil, enabled: canSave) { commit(excused: $0) }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
        }
    }

    private func scopeSection(_ sched: DaySchedule) -> some View {
        let names = sched.slots.filter { picked.contains($0.number) }.map { store.subjectName($0.subject) }.joined(separator: ", ")
        return Section {
            ChoiceChip(title: "Весь день · \(pairsText(sched.slots.count))", systemImage: "calendar", selected: whole) {
                Haptics.selection()
                whole = true
                picked.removeAll()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(sched.slots) { s in
                    PairSquare(number: s.number,
                               selected: !whole && picked.contains(s.number),
                               marked: store.absence(on: date, lesson: s.number) != nil) {
                        Haptics.selection()
                        togglePair(s.number)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Что пропустили")
        } footer: {
            if !whole && !names.isEmpty { Text(names) }
        }
    }

    private func togglePair(_ n: Int) {
        if whole {
            whole = false
            picked = [n]
        } else if picked.contains(n) {
            picked.remove(n)
            if picked.isEmpty { whole = true }
        } else {
            picked.insert(n)
        }
    }

    /// Полная форма с уже подставленными парой и предметом.
    private var detailsForm: some View {
        var lesson: Int?
        var subj: String?
        if let f = fixedSlots, f.count == 1 {
            lesson = f[0].number
            subj = subject(for: f[0])
        } else if !locked && !whole && picked.count == 1 {
            lesson = picked.first
        }
        return AbsenceForm(edit: nil, date: date, lesson: lesson, subject: subj, hours: hours, close: close)
    }

    private func commit(excused: Bool) {
        guard canSave else { return }
        let store = self.store
        let date = self.date
        let before = store.snapshotDay(date)

        var items: [Absence] = []
        if let slots = slots {
            for s in slots {
                let old = store.absence(on: date, lesson: s.number)
                items.append(Absence(id: old?.id ?? newId(), date: date, lesson: s.number, subject: subject(for: s),
                                     hours: hours, excused: excused, note: old?.note ?? ""))
            }
        } else {
            items.append(Absence(id: newId(), date: date, lesson: 0, subject: manualSubject, hours: hours, excused: excused))
        }

        store.saveAbsences(items)
        Haptics.success()
        close()

        let total = items.reduce(0) { $0 + $1.hours }
        let kind = excused ? "по уважительной" : "без уважительной"
        let msg = items.count == 1
            ? "Пропуск: \(hoursText(total)) · \(kind)"
            : "Пропуск: \(pairsText(items.count)) · \(hoursText(total)) · \(kind)"
        toaster.show(msg) { store.restoreDay(date, before) }
    }
}

// MARK: - Подробная форма

/// Полная форма: дата, пара, предмет, часы, причина и заметка.
struct AbsenceForm: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    let edit: Absence?
    let close: () -> Void

    @State private var date: Date
    @State private var hours: Int
    @State private var excused: Bool
    @State private var note: String
    @State private var lesson: Int
    @State private var subject: String
    @State private var confirmDelete = false

    init(edit: Absence?, date: Date?, lesson: Int?, subject: String?, hours: Int, close: @escaping () -> Void) {
        self.edit = edit
        self.close = close
        _date = State(initialValue: edit?.date ?? date ?? today())
        _hours = State(initialValue: edit?.hours ?? hours)
        _excused = State(initialValue: edit?.excused ?? false)
        _note = State(initialValue: edit?.note ?? "")
        _lesson = State(initialValue: edit?.lesson ?? lesson ?? 0)
        _subject = State(initialValue: edit?.subject ?? subject ?? "")
    }

    private var editing: Bool { edit != nil }
    private var canSave: Bool { !subject.isEmpty || editing }

    private var suggested: [String] {
        guard let s = store.cachedSchedule(on: date) else { return [] }
        return s.slots.flatMap { $0.subjects }
    }

    var body: some View {
        Form {
            Section {
                DatePicker(selection: $date, displayedComponents: .date) {
                    Label("Дата", systemImage: "calendar")
                }
                Picker(selection: $lesson) {
                    Text("Не указана").tag(0)
                    ForEach(1...8, id: \.self) { Text("\($0) пара").tag($0) }
                } label: {
                    Label("Пара", systemImage: "number")
                }
                .onChange(of: lesson) { _, n in
                    if let hit = store.cachedSchedule(on: date)?.slots.first(where: { $0.number == n }) {
                        subject = hit.subject
                    }
                }
                SubjectField(subject: $subject, suggested: suggested)
            } footer: {
                if !canSave { Text("Выберите предмет") }
            }

            Section("Сколько часов") {
                HoursPicker(hours: $hours)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Причина") {
                Picker("Причина", selection: $excused) {
                    Text("Без уважительной").tag(false)
                    Text("По уважительной").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Заметка") {
                TextField("Необязательно", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            if editing {
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Удалить пропуск", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(editing ? "Изменить пропуск" : "Новый пропуск")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }.disabled(!canSave)
            }
        }
        .confirmationDialog("Удалить пропуск?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { delete() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func save() {
        guard canSave else { return }
        let store = self.store
        let date = self.date
        let beforeNew = store.snapshotDay(date)
        let beforeOld: [Absence]? = {
            guard let e = edit, !sameDay(e.date, date) else { return nil }
            return store.snapshotDay(e.date)
        }()
        let oldDate = edit?.date

        store.saveAbsence(Absence(id: edit?.id ?? newId(), date: date, lesson: lesson, subject: subject, hours: hours,
                                  excused: excused, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        Haptics.success()
        close()
        let message = edit == nil ? "Пропуск добавлен · \(hoursText(hours))" : "Пропуск изменён"
        toaster.show(message) {
            store.restoreDay(date, beforeNew)
            if let beforeOld = beforeOld, let oldDate = oldDate { store.restoreDay(oldDate, beforeOld) }
        }
    }

    private func delete() {
        guard let a = edit else { return }
        let store = self.store
        let before = store.snapshotDay(a.date)
        store.deleteAbsence(a.id)
        Haptics.medium()
        close()
        toaster.show("Пропуск удалён") { store.restoreDay(a.date, before) }
    }
}
