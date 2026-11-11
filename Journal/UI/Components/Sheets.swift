import SwiftUI

// MARK: - Выбор группы

/// Список групп с сайта колледжа, поиск и ввод номера вручную.
struct GroupPickerView: View {
    @Environment(ScheduleRepo.self) private var repo

    let selected: String
    var title: String = "Группа"
    let onPick: (String) -> Void

    @State private var groups: [String] = []
    @State private var loading = true
    @State private var offline = false
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [String] { trimmed.isEmpty ? groups : groups.filter { $0.contains(trimmed) } }

    private var manualValid: Bool {
        let u = trimmed.unicodeScalars
        return (3...5).contains(u.count) && u.allSatisfy { $0.value >= 48 && $0.value <= 57 } && !groups.contains(trimmed)
    }

    var body: some View {
        List {
            if loading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Загружаем список групп…").foregroundStyle(.secondary)
                    }
                }
            } else if offline {
                Section {
                    ContentUnavailableView {
                        Label("Нет подключения", systemImage: "wifi.slash")
                    } description: {
                        Text("Не удалось загрузить список групп. Проверьте интернет или введите номер группы вручную.")
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                            .buttonStyle(.glass)
                    }
                }
            } else if groups.isEmpty {
                Section {
                    ContentUnavailableView("Список пуст", systemImage: "person.3",
                                           description: Text("Расписание на ближайшие дни ещё не опубликовано. Введите номер группы вручную."))
                }
            } else {
                Section {
                    if filtered.isEmpty {
                        Text("Группа не найдена").foregroundStyle(.secondary)
                    }
                    ForEach(filtered, id: \.self) { g in
                        Button {
                            Haptics.selection()
                            onPick(g)
                        } label: {
                            HStack {
                                Text("Группа \(g)").foregroundStyle(.primary)
                                Spacer()
                                if g == selected {
                                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } footer: {
                    Text("Всего групп: \(groups.count)")
                }
            }

            if manualValid {
                Section {
                    Button {
                        Haptics.selection()
                        onPick(trimmed)
                    } label: {
                        Label("Использовать группу \(trimmed)", systemImage: "keyboard")
                    }
                } footer: {
                    Text("Этой группы нет в списке на сайте, но номер можно ввести вручную.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Номер группы")
        .task { await load() }
    }

    private func load() async {
        loading = true
        offline = false
        let result = await repo.service.listGroups()
        if Task.isCancelled { return }
        groups = result.groups
        offline = result.offline
        loading = false
    }
}

// MARK: - Выбор даты

struct DatePickerSheet: View {
    let initial: Date
    let onPick: (Date) -> Void
    let close: () -> Void

    @State private var date: Date

    init(initial: Date, onPick: @escaping (Date) -> Void, close: @escaping () -> Void) {
        self.initial = initial
        self.onPick = onPick
        self.close = close
        _date = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("Дата", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .navigationTitle("Выбор даты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
            ToolbarItem(placement: .primaryAction) {
                Button("Сегодня") { date = today() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") {
                    onPick(dateOnly(date))
                    close()
                }
            }
        }
    }
}

// MARK: - Семестр

struct SemesterSheet: View {
    @Environment(AppStore.self) private var store
    let semester: Semester
    let hours: Int
    let close: () -> Void

    var body: some View {
        let level = limitLevel(hours, warnFrom: kSemesterWarnFrom, limit: kSemesterLimit)
        let color: Color = level == .reached ? .red : (level == .near ? warnColor : .accentColor)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(hours)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(color)
                        Text("из \(kSemesterLimit) ч").font(.title3).foregroundStyle(.secondary)
                    }
                    ProgressBar(value: Double(hours) / Double(kSemesterLimit), color: color, height: 10)
                    Text(semesterStatusText(hours))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                LabeledContent("Учебный год", value: semester.years)
                LabeledContent("Семестр", value: semester.title)
                LabeledContent("С", value: fullDate(semester.start))
                LabeledContent("По", value: fullDate(semester.end))
            }

            Section {
                NavigationLink {
                    AbsenceSettingsView()
                } label: {
                    Label("Настройки пропусков", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Семестр")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Готово") { close() } }
        }
    }
}

func semesterStatusText(_ hours: Int) -> String {
    let left = kSemesterLimit - hours
    if left <= 0 { return "Лимит в \(kSemesterLimit) ч за семестр исчерпан." }
    return "До лимита осталось \(hoursText(left)). Считаются только пропуски без уважительной причины."
}

// MARK: - Хост шторок

private struct SheetHost: ViewModifier {
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        @Bindable var router = router
        content.sheet(item: $router.sheet) { sheet in
            SheetContent(sheet: sheet)
        }
    }
}

extension View {
    /// Подключает все шторки приложения к [Router].
    func sheetHost() -> some View { modifier(SheetHost()) }
}

private struct SheetContent: View {
    let sheet: ActiveSheet

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ScheduleRepo.self) private var repo
    @Environment(Toaster.self) private var toaster

    var body: some View {
        NavigationStack { content }
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
    }

    private var detents: Set<PresentationDetent> {
        switch sheet {
        case .absenceQuick, .absenceLesson, .absenceWholeDay: return [.medium, .large]
        case .datePicker: return [.medium]
        case .semester, .bells, .lesson: return [.medium, .large]
        default: return [.large]
        }
    }

    @ViewBuilder
    private var content: some View {
        let close: () -> Void = { router.dismiss() }
        switch sheet {
        case .grade(let edit, let subject, let date):
            GradeForm(edit: edit, subject: subject, date: date, close: close)
        case .absenceQuick(let date, let lesson):
            AbsenceQuickForm(date: date, lesson: lesson, fixedSlots: nil, wholeDay: false,
                             hours: store.settings.absenceHours, close: close)
        case .absenceLesson(let date, let slot):
            AbsenceQuickForm(date: date, lesson: slot.number, fixedSlots: [slot], wholeDay: false,
                             hours: store.settings.absenceHours, close: close)
        case .absenceWholeDay(let date, let slots):
            AbsenceQuickForm(date: date, lesson: nil, fixedSlots: slots, wholeDay: true,
                             hours: store.settings.absenceHours, close: close)
        case .absenceForm(let edit, let date):
            AbsenceForm(edit: edit, date: date, lesson: nil, subject: nil, hours: store.settings.absenceHours, close: close)
        case .lesson(let date, let slot):
            LessonSheet(date: date, slot: slot, close: close)
        case .mark(let date, let lesson, let edit):
            MarkForm(edit: edit, date: date, lesson: lesson, close: close)
        case .bells(let date):
            DayBellsSheet(date: date, close: close)
        case .group:
            GroupPickerView(selected: store.settings.group) { group in
                let changed = group != store.settings.group
                store.setGroup(group)
                router.dismiss()
                if changed {
                    toaster.show("Группа \(group)")
                    Task { await repo.prefetch(force: true, respectSetting: false) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
            }
        case .datePicker(let selected, let onPick):
            DatePickerSheet(initial: selected, onPick: onPick, close: close)
        case .semester(let semester, let hours):
            SemesterSheet(semester: semester, hours: hours, close: close)
        }
    }
}
