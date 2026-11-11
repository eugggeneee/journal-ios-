import SwiftUI

private enum AbsenceFilter: String, CaseIterable, Identifiable {
    case all, unexcused, excused
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Все"
        case .unexcused: return "Без уважит."
        case .excused: return "По уважит."
        }
    }
}

private enum AbsenceMode: String, CaseIterable, Identifiable {
    case dates, subjects
    var id: String { rawValue }
    var title: String { self == .dates ? "По датам" : "По предметам" }
}

// MARK: - Вкладка

struct AbsencesPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Toaster.self) private var toaster

    @State private var filter: AbsenceFilter = .all
    @State private var mode: AbsenceMode = .dates

    private var filtered: [Absence] {
        switch filter {
        case .all: return store.absences
        case .unexcused: return store.absences.filter { !$0.excused }
        case .excused: return store.absences.filter { $0.excused }
        }
    }

    var body: some View {
        let now = Date()
        let sem = store.semester(on: now)
        let monthHours = monthUnexcusedHours(store.absences, now)
        let semHours = semesterUnexcusedHours(store.absences, sem)
        let monthLevel = limitLevel(monthHours, warnFrom: kMonthWarnFrom, limit: kMonthLimit)
        let semLevel = limitLevel(semHours, warnFrom: kSemesterWarnFrom, limit: kSemesterLimit)

        NavigationStack {
            Group {
                if store.absences.isEmpty {
                    ContentUnavailableView {
                        Label("Пропусков нет", systemImage: "checkmark.seal")
                    } description: {
                        Text("Отмечайте пропуски на экране расписания — здесь появится сводка и лимиты.")
                    } actions: {
                        Button("Добавить пропуск") { router.present(.absenceForm(edit: nil, date: nil)) }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        let monthKeyStr = monthDismissKey(now)
                        let semKeyStr = semesterDismissKey(sem)
                        if monthLevel != .ok && store.dismissedLevel(monthKeyStr) < monthLevel.rawValue {
                            banner(level: monthLevel, hours: monthHours, limit: kMonthLimit,
                                   title: "Месяц: \(monthWord(now))", key: monthKeyStr)
                        }
                        if semLevel != .ok && store.dismissedLevel(semKeyStr) < semLevel.rawValue {
                            banner(level: semLevel, hours: semHours, limit: kSemesterLimit,
                                   title: "\(sem.title) \(sem.years)", key: semKeyStr)
                        }

                        Section {
                            summaryCard
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        Section("Лимиты") {
                            LimitRow(title: "В этом месяце", subtitle: monthYear(now), hours: monthHours,
                                     limit: kMonthLimit, level: monthLevel)
                            Button {
                                router.present(.semester(sem, hours: semHours))
                            } label: {
                                LimitRow(title: sem.title, subtitle: "Учебный год \(sem.years)", hours: semHours,
                                         limit: kSemesterLimit, level: semLevel, chevron: true)
                            }
                            .foregroundStyle(.primary)
                        }

                        Section {
                            Picker("Режим", selection: $mode) {
                                ForEach(AbsenceMode.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Picker("Показывать", selection: $filter) {
                                ForEach(AbsenceFilter.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)

                        if filtered.isEmpty {
                            Section {
                                ContentUnavailableView("Ничего не найдено", systemImage: "line.3.horizontal.decrease.circle",
                                                       description: Text("Измените фильтр, чтобы увидеть пропуски."))
                            }
                        } else if mode == .dates {
                            datesSections
                        } else {
                            subjectsSection
                        }
                    }
                }
            }
            .navigationTitle("Пропуски")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.present(.absenceForm(edit: nil, date: nil))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить пропуск")
                }
            }
        }
        .toastHost()
    }

    // MARK: Предупреждение

    private func banner(level: LimitLevel, hours: Int, limit: Int, title: String, key: String) -> some View {
        let reached = level == .reached
        let color: Color = reached ? .red : warnColor
        return Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: reached ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reached ? "Лимит исчерпан" : "Лимит близко").font(.headline)
                    Text("\(title): \(hours) из \(limit) ч без уважительной причины.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Скрыть") { dismiss(key: key, level: level) }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 2)
                        .buttonStyle(.plain)
                        .foregroundStyle(color)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(color.opacity(0.14))
    }

    private func dismiss(key: String, level: LimitLevel) {
        let store = self.store
        let previous = store.dismissedLevel(key)
        store.dismissLimit(key, level: level.rawValue)
        Haptics.selection()
        toaster.show("Предупреждение скрыто") { store.undoDismissLimit(key, previous: previous) }
    }

    // MARK: Сводка

    private var summaryCard: some View {
        let st = AbsenceStats.of(store.absences)
        return HeroCard(tint: st.unexcusedHours >= kMonthWarnFrom ? warnColor : .accentColor) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Всего пропущено").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            AnimatedNumber(value: Double(st.totalHours), text: "\(st.totalHours)")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                            Text("ч").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Pill(text: "\(st.unexcusedHours) ч без уважит.", systemImage: "xmark.circle.fill", color: .red)
                    Pill(text: "\(st.excusedHours) ч по уважит.", systemImage: "checkmark.circle.fill", color: .green)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: По датам

    @ViewBuilder
    private var datesSections: some View {
        let sortedList = filtered.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.lesson > b.lesson
        }
        let groups = Dictionary(grouping: sortedList) { monthKey($0.date) }
        let keys = groups.keys.sorted(by: >)
        ForEach(keys, id: \.self) { key in
            let list = groups[key] ?? []
            let hours = list.reduce(0) { $0 + $1.hours }
            Section {
                ForEach(list) { a in AbsenceRow(absence: a) }
            } header: {
                HStack {
                    Text(list.first.map { monthYear($0.date) } ?? key)
                    Spacer()
                    Text("\(hours) ч")
                }
            }
        }
    }

    // MARK: По предметам

    private var subjectsSection: some View {
        let st = AbsenceStats.of(filtered)
        let names = st.bySubjectHours.keys.sorted { (st.bySubjectHours[$0] ?? 0) > (st.bySubjectHours[$1] ?? 0) }
        return Section("Предметы") {
            ForEach(names, id: \.self) { s in
                HStack(spacing: 14) {
                    NumberBadge(text: "\(st.bySubjectHours[s] ?? 0)", color: .red, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.isEmpty ? "Без предмета" : store.subjectName(s)).font(.body.weight(.semibold)).lineLimit(2)
                        let count = st.bySubjectCount[s] ?? 0
                        let last = st.lastBySubject[s].map { " · последний \(shortDate($0))" } ?? ""
                        Text("\(absencesText(count))\(last)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("ч").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Строки

struct AbsenceRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Toaster.self) private var toaster

    let absence: Absence

    var body: some View {
        let color = absenceColor(excused: absence.excused)
        Button {
            router.present(.absenceForm(edit: absence, date: nil))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: absence.excused ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(absence.subject.isEmpty ? "Без предмета" : store.subjectName(absence.subject))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    let lesson = absence.lesson > 0 ? "\(absence.lesson) пара · " : ""
                    Text("\(lesson)\(longDate(absence.date))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !absence.note.isEmpty {
                        Text(absence.note).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text("\(absence.hours) ч").font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { remove() } label: { Label("Удалить", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { toggleExcused() } label: {
                Label(absence.excused ? "Без уважит." : "По уважит.",
                      systemImage: absence.excused ? "xmark.circle" : "checkmark.circle")
            }
            .tint(absence.excused ? .red : .green)
        }
        .accessibilityLabel("\(absence.hours) ч, \(absence.excused ? "по уважительной" : "без уважительной"), \(longDate(absence.date))")
    }

    private func remove() {
        let store = self.store
        let a = absence
        let before = store.snapshotDay(a.date)
        store.deleteAbsence(a.id)
        Haptics.medium()
        toaster.show("Пропуск удалён") { store.restoreDay(a.date, before) }
    }

    private func toggleExcused() {
        let store = self.store
        let a = absence
        let before = store.snapshotDay(a.date)
        var changed = a
        changed.excused.toggle()
        store.saveAbsence(changed)
        Haptics.selection()
        toaster.show(changed.excused ? "Пропуск по уважительной причине" : "Пропуск без уважительной причины") {
            store.restoreDay(a.date, before)
        }
    }
}

// MARK: - Лимит

struct LimitRow: View {
    let title: String
    let subtitle: String
    let hours: Int
    let limit: Int
    let level: LimitLevel
    var chevron: Bool = false

    private var color: Color {
        switch level {
        case .ok: return .accentColor
        case .near: return warnColor
        case .reached: return .red
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, Double(hours) / Double(limit))))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: hours)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(hours) / \(limit) ч").font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                if level != .ok {
                    Text(level == .reached ? "лимит исчерпан" : "лимит близко").font(.caption).foregroundStyle(color)
                }
            }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
