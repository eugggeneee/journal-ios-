import SwiftUI
import Charts

// MARK: - Фильтры

enum GradePeriod: String, CaseIterable, Identifiable {
    case all, semester, month, week
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Всё время"
        case .semester: return "Текущий семестр"
        case .month: return "Последние 30 дней"
        case .week: return "Последние 7 дней"
        }
    }
}

enum SubjectSort: String, CaseIterable, Identifiable {
    case name, average, recent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "По названию"
        case .average: return "По среднему баллу"
        case .recent: return "По последней оценке"
        }
    }
}

enum GradesMode: String, CaseIterable, Identifiable {
    case subjects, journal
    var id: String { rawValue }
    var title: String { self == .subjects ? "Предметы" : "Журнал" }
}

// MARK: - Вкладка

struct GradesPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Toaster.self) private var toaster

    @State private var mode: GradesMode = .subjects
    @State private var period: GradePeriod = .all
    @State private var sort: SubjectSort = .name

    private var filtered: [Grade] {
        let t = today()
        switch period {
        case .all: return store.grades
        case .semester:
            let s = store.semester()
            return store.grades.filter { $0.date >= s.start && $0.date <= s.end }
        case .month: return store.grades.filter { $0.date >= addDays(t, -29) }
        case .week: return store.grades.filter { $0.date >= addDays(t, -6) }
        }
    }

    private func sorted(_ list: [SubjectStat]) -> [SubjectStat] {
        switch sort {
        case .name:
            return list.sorted { store.subjectName($0.subject).localizedCompare(store.subjectName($1.subject)) == .orderedAscending }
        case .average:
            return list.sorted { $0.average > $1.average }
        case .recent:
            return list.sorted { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }
        }
    }

    var body: some View {
        let stats = GradeStats.of(filtered)
        NavigationStack {
            Group {
                if store.grades.isEmpty {
                    ContentUnavailableView {
                        Label("Оценок пока нет", systemImage: "star")
                    } description: {
                        Text("Добавляйте оценки — приложение посчитает средний балл по каждому предмету.")
                    } actions: {
                        Button("Добавить оценку") { router.present(.grade(edit: nil, subject: nil, date: nil)) }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        Section {
                            summary(stats)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        Section {
                            Picker("Режим", selection: $mode) {
                                ForEach(GradesMode.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }

                        if stats.count == 0 {
                            Section {
                                ContentUnavailableView("Нет оценок за период", systemImage: "calendar.badge.exclamationmark",
                                                       description: Text("Выберите другой период в меню фильтров."))
                            }
                        } else if mode == .subjects {
                            subjectsSection(stats)
                        } else {
                            journalSections(filtered)
                        }
                    }
                }
            }
            .navigationTitle("Оценки")
            .navigationDestination(for: String.self) { subject in
                SubjectDetailView(subject: subject)
            }
            .toolbar {
                if !store.grades.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Период", selection: $period) {
                                ForEach(GradePeriod.allCases) { Text($0.title).tag($0) }
                            }
                            if mode == .subjects {
                                Picker("Сортировка", selection: $sort) {
                                    ForEach(SubjectSort.allCases) { Text($0.title).tag($0) }
                                }
                            }
                        } label: {
                            Image(systemName: period == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        }
                        .accessibilityLabel("Фильтры")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.present(.grade(edit: nil, subject: nil, date: nil))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить оценку")
                }
            }
        }
        .toastHost()
    }

    // MARK: Сводка

    private func summary(_ stats: GradeStats) -> some View {
        let avg = stats.average
        let tint: Color = avg.map { gradeFill($0) } ?? .accentColor
        return HeroCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Средний балл").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        AnimatedNumber(value: avg ?? 0, text: avg.map(fmtAvg) ?? "—")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(avg.map { gradeText($0) } ?? Color.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(stats.count)").font(.title2.weight(.bold)).monospacedDigit()
                        Text(plural(stats.count, "оценка", "оценки", "оценок")).font(.footnote).foregroundStyle(.secondary)
                        Text(subjectsText(stats.subjects.count)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                DistributionChart(distribution: stats.distribution)
                    .frame(height: 84)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Предметы

    private func subjectsSection(_ stats: GradeStats) -> some View {
        Section {
            ForEach(sorted(stats.subjects)) { st in
                NavigationLink(value: st.subject) {
                    SubjectRow(stat: st)
                }
            }
        } header: {
            Text("\(subjectsText(stats.subjects.count)) · \(period.title.lowercased())")
        }
    }

    // MARK: Журнал

    @ViewBuilder
    private func journalSections(_ list: [Grade]) -> some View {
        let groups = Dictionary(grouping: list) { dateOnly($0.date) }
        let days = groups.keys.sorted(by: >)
        ForEach(days, id: \.self) { d in
            Section(dayCaption(d)) {
                ForEach((groups[d] ?? []).sorted { $0.id > $1.id }) { g in
                    GradeRow(grade: g, showSubject: true)
                }
            }
        }
    }
}

// MARK: - Строки

struct GradeRow: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Toaster.self) private var toaster

    let grade: Grade
    var showSubject: Bool

    var body: some View {
        Button {
            router.present(.grade(edit: grade, subject: nil, date: nil))
        } label: {
            HStack(spacing: 14) {
                NumberBadge(text: "\(grade.value)", color: gradeFill(grade.value), textColor: gradeText(grade.value), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(showSubject ? store.subjectName(grade.subject) : dayCaption(grade.date))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    let detail = [grade.kind, grade.note].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { remove() } label: { Label("Удалить", systemImage: "trash") }
        }
        .accessibilityLabel("\(grade.value), \(store.subjectName(grade.subject)), \(dayCaption(grade.date))")
    }

    private func remove() {
        let store = self.store
        let g = grade
        store.deleteGrade(g.id)
        Haptics.medium()
        toaster.show("Оценка удалена") { store.saveGrade(g) }
    }
}

struct SubjectRow: View {
    @Environment(AppStore.self) private var store
    let stat: SubjectStat

    var body: some View {
        HStack(spacing: 14) {
            NumberBadge(text: fmtAvg(stat.average), color: gradeFill(stat.average), textColor: gradeText(stat.average), size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.subjectName(stat.subject)).font(.body.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(gradesText(stat.count)).font(.subheadline).foregroundStyle(.secondary)
                    if let impact = stat.lastImpact, abs(impact) >= 0.005 {
                        Image(systemName: impact > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(impact > 0 ? Color.green : Color.red)
                    }
                }
            }
            Spacer(minLength: 8)
            SparkBars(grades: Array(stat.grades.suffix(8)))
        }
        .padding(.vertical, 2)
    }
}

/// Мини-график последних оценок предмета.
struct SparkBars: View {
    let grades: [Grade]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(grades.enumerated()), id: \.offset) { _, g in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(gradeFill(g.value))
                    .frame(width: 5, height: 6 + CGFloat(g.value) * 2.4)
            }
        }
        .frame(height: 32, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Распределение оценок: сколько раз получена каждая из 10.
struct DistributionChart: View {
    let distribution: [Int]

    var body: some View {
        Chart {
            ForEach(0..<10, id: \.self) { i in
                BarMark(x: .value("Оценка", "\(i + 1)"), y: .value("Количество", distribution[i]))
                    .foregroundStyle(gradeFill(i + 1))
                    .cornerRadius(4)
            }
        }
        .chartYAxis(.hidden)
        .accessibilityLabel("Распределение оценок")
    }
}

// MARK: - Предмет

struct SubjectDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    let subject: String

    var body: some View {
        let grades = store.grades(of: subject)
        let stat = GradeStats.of(grades).subjects.first
        List {
            if let stat = stat {
                Section {
                    HeroCard(tint: gradeFill(stat.average)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Средний балл").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(fmtAvg(stat.average))
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                        .foregroundStyle(gradeText(stat.average))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(gradesText(stat.count)).font(.subheadline.weight(.semibold))
                                    if let impact = stat.lastImpact, abs(impact) >= 0.005 {
                                        Label(String(format: "%+.2f", impact).replacingOccurrences(of: ".", with: ","),
                                              systemImage: impact > 0 ? "arrow.up.right" : "arrow.down.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(impact > 0 ? Color.green : Color.red)
                                    }
                                }
                            }
                            if stat.count >= 2 {
                                TrendChart(grades: stat.grades).frame(height: 120)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                Section("Все оценки") {
                    ForEach(stat.grades.reversed()) { g in
                        GradeRow(grade: g, showSubject: false)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView("Оценок нет", systemImage: "star")
                }
            }
        }
        .navigationTitle(store.subjectName(subject))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.grade(edit: nil, subject: subject, date: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Добавить оценку по предмету")
            }
        }
    }
}

/// Динамика оценок по порядку получения.
struct TrendChart: View {
    let grades: [Grade]

    var body: some View {
        Chart {
            ForEach(Array(grades.enumerated()), id: \.offset) { i, g in
                LineMark(x: .value("№", i + 1), y: .value("Оценка", g.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                PointMark(x: .value("№", i + 1), y: .value("Оценка", g.value))
                    .foregroundStyle(gradeFill(g.value))
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: 0...10)
        .chartYAxis {
            AxisMarks(values: [0, 5, 10])
        }
        .chartXAxis(.hidden)
        .accessibilityLabel("Динамика оценок")
    }
}
