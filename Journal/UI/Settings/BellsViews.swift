import SwiftUI

/// Привязка минут от полуночи к выбору времени.
private func minuteBinding(_ value: Binding<Int>) -> Binding<Date> {
    Binding<Date>(
        get: {
            Cal.cal.date(bySettingHour: min(23, max(0, value.wrappedValue / 60)),
                         minute: min(59, max(0, value.wrappedValue % 60)), second: 0, of: today()) ?? today()
        },
        set: { value.wrappedValue = minuteOfDay($0) }
    )
}

// MARK: - Звонки: главный экран

/// Расписание звонков: готовые варианты, автозаполнение и правка каждой пары.
struct BellsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    @State private var key: String
    @State private var showPlan = false

    init(initialKey: String = kBellWeek) {
        _key = State(initialValue: initialKey)
    }

    private var profile: BellProfile { store.settings.bell(key) }

    var body: some View {
        List {
            Section {
                Picker("Дни", selection: $key) {
                    ForEach(kBellKeys, id: \.self) { Text(bellTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            } footer: {
                Text(key == kBellSat ? "Это время действует по субботам." : "Это время действует с понедельника по пятницу.")
            }

            if let problem = profile.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(warnColor)
                }
            }

            Section("Готовые расписания") {
                ForEach(kBellPresets.filter { $0.key == key }) { preset in
                    Button {
                        apply(preset.profile, message: preset.title)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title).foregroundStyle(.primary)
                                Text(preset.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.sameAs(preset.profile) {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                Button {
                    showPlan = true
                } label: {
                    Label("Заполнить автоматически", systemImage: "wand.and.stars")
                }
            }

            Section {
                ForEach(1...kMaxPairs, id: \.self) { n in
                    NavigationLink {
                        BellSlotEditor(number: n, key: key)
                    } label: {
                        pairRow(n)
                    }
                    if let gap = gapLabel(profile, n) {
                        Label(gap, systemImage: profile.isLunchAfter(n) ? "fork.knife" : "cup.and.saucer")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text("Пары")
            } footer: {
                Text("Нажмите на пару, чтобы изменить время, добавить перерыв внутри пары или обед.")
            }

            if !profile.isEmpty || profile.lunchAfter > 0 {
                Section {
                    Button(role: .destructive) {
                        apply(BellProfile(), message: "Звонки очищены")
                    } label: {
                        Label("Очистить расписание звонков", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Звонки")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPlan) {
            NavigationStack { BellPlanForm(key: key) { showPlan = false } }
                .presentationDetents([.large])
        }
    }

    @ViewBuilder
    private func pairRow(_ n: Int) -> some View {
        if let s = profile[n] {
            HStack(spacing: 12) {
                NumberBadge(text: "\(n)", color: .accentColor, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slotRange(s)).font(.body.weight(.semibold)).monospacedDigit()
                    Text(s.hasBreak
                         ? "\(halvesText(s)) · \(innerBreakWord(s)) \(shortRange(s.breakStart ?? 0, s.breakEnd ?? 0))"
                         : minText(s.minutes))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 12) {
                NumberBadge(text: "\(n)", color: .gray, size: 40)
                Text("Не задана").foregroundStyle(.secondary)
            }
        }
    }

    private func apply(_ new: BellProfile, message: String) {
        let store = self.store
        let key = self.key
        let old = store.settings.bell(key)
        store.setBellProfile(key, new)
        Haptics.success()
        toaster.show(new.isEmpty ? message : "Применено: \(message)") { store.setBellProfile(key, old) }
    }
}

// MARK: - Правка одной пары

struct BellSlotEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster
    @Environment(\.dismiss) private var dismiss

    let number: Int
    let key: String

    @State private var start: Int
    @State private var end: Int
    @State private var hasBreak: Bool
    @State private var breakStart: Int
    @State private var breakEnd: Int
    @State private var lunchAfter: Bool
    @State private var existed: Bool
    @State private var loaded = false

    init(number: Int, key: String) {
        self.number = number
        self.key = key
        _start = State(initialValue: 8 * 60 + 20)
        _end = State(initialValue: 10 * 60)
        _hasBreak = State(initialValue: false)
        _breakStart = State(initialValue: 9 * 60 + 5)
        _breakEnd = State(initialValue: 9 * 60 + 15)
        _lunchAfter = State(initialValue: false)
        _existed = State(initialValue: false)
    }

    private var profile: BellProfile { store.settings.bell(key) }

    private var candidate: BellSlot {
        BellSlot(start: start, end: end, breakStart: hasBreak ? breakStart : nil, breakEnd: hasBreak ? breakEnd : nil)
    }

    private var problem: String? {
        if !candidate.valid { return "Конец должен быть позже начала, а перерыв — внутри пары" }
        return profile.withSlot(number, candidate).problem
    }

    var body: some View {
        Form {
            Section("Пара") {
                DatePicker("Начало", selection: startBinding, displayedComponents: .hourAndMinute)
                DatePicker("Конец", selection: minuteBinding($end), displayedComponents: .hourAndMinute)
            }

            Section {
                Toggle("Перерыв внутри пары", isOn: $hasBreak.animation())
                if hasBreak {
                    DatePicker("Перерыв с", selection: minuteBinding($breakStart), displayedComponents: .hourAndMinute)
                    DatePicker("Перерыв до", selection: minuteBinding($breakEnd), displayedComponents: .hourAndMinute)
                }
            } footer: {
                if hasBreak, candidate.valid {
                    Text("\(halvesText(candidate)) · \(innerBreakWord(candidate)) \(minText(candidate.breakMinutes))")
                }
            }

            if number < kMaxPairs {
                Section {
                    Toggle("Обед после этой пары", isOn: $lunchAfter)
                } footer: {
                    Text("Перерыв между этой и следующей парой будет подписан как обед.")
                }
            }

            if let problem = problem {
                Section { Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(warnColor) }
            }

            if existed {
                Section {
                    Button(role: .destructive) { remove() } label: {
                        Label("Убрать пару", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("\(number) пара")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }.disabled(problem != nil)
            }
        }
        .onAppear {
            if !loaded {
                loaded = true
                load()
            }
        }
    }

    /// При ручной смене начала сдвигаем конец и перерыв вместе с ним, чтобы длительность пары сохранилась.
    private var startBinding: Binding<Date> {
        Binding<Date>(
            get: { minuteBinding($start).wrappedValue },
            set: { newDate in
                let new = minuteOfDay(newDate)
                let d = new - start
                start = new
                end += d
                breakStart += d
                breakEnd += d
            }
        )
    }

    private func load() {
        let p = profile
        if let s = p[number] {
            existed = true
            let e = s.end
            let bs = s.breakStart ?? (s.start + s.minutes / 2 - 5)
            let be = s.breakEnd ?? (s.start + s.minutes / 2 + 5)
            start = s.start
            end = e
            breakStart = bs
            breakEnd = be
            hasBreak = s.hasBreak
        } else {
            var s = 8 * 60 + 20
            if let prev = (1..<number).reversed().compactMap({ p[$0] }).first { s = prev.end + 10 }
            s = min(s, 24 * 60 - 100)
            start = s
            end = s + 90
            breakStart = s + 40
            breakEnd = s + 50
            hasBreak = false
        }
        lunchAfter = p.lunchAfter == number
    }

    private func save() {
        guard problem == nil else { return }
        let store = self.store
        let key = self.key
        let old = store.settings.bell(key)
        var new = old.withSlot(number, candidate)
        if lunchAfter {
            new = new.withLunch(number)
        } else if new.lunchAfter == number {
            new = new.withLunch(0)
        }
        store.setBellProfile(key, new)
        Haptics.success()
        dismiss()
        toaster.show("\(number) пара сохранена") { store.setBellProfile(key, old) }
    }

    private func remove() {
        let store = self.store
        let key = self.key
        let old = store.settings.bell(key)
        var new = old.withSlot(number, nil)
        if new.lunchAfter == number { new = new.withLunch(0) }
        store.setBellProfile(key, new)
        Haptics.medium()
        dismiss()
        toaster.show("\(number) пара убрана") { store.setBellProfile(key, old) }
    }
}

// MARK: - Автозаполнение

struct BellPlanForm: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    let key: String
    let close: () -> Void

    @State private var plan = BellPlan()

    private var preview: BellProfile { generateBells(plan) }

    var body: some View {
        Form {
            Section("Начало") {
                DatePicker("Первая пара", selection: minuteBinding($plan.firstStart), displayedComponents: .hourAndMinute)
                Stepper(value: $plan.count, in: 1...kMaxPairs) {
                    LabeledContent("Количество пар", value: "\(plan.count)")
                }
            }

            Section("Длительность") {
                Stepper(value: $plan.pairMinutes, in: 30...180, step: 5) {
                    LabeledContent("Пара", value: minText(plan.pairMinutes))
                }
                Stepper(value: $plan.innerBreak, in: 0...30, step: 5) {
                    LabeledContent("Перерыв внутри пары", value: plan.innerBreak == 0 ? "нет" : minText(plan.innerBreak))
                }
                Stepper(value: $plan.breakMinutes, in: 0...60, step: 5) {
                    LabeledContent("Между парами", value: minText(plan.breakMinutes))
                }
            }

            Section("Обед") {
                Picker("Обед после пары", selection: $plan.lunchAfter) {
                    Text("Нет").tag(0)
                    ForEach(Array(1..<max(1, plan.count)), id: \.self) { Text("\($0)").tag($0) }
                }
                if plan.lunchAfter > 0 {
                    Stepper(value: $plan.lunchMinutes, in: 10...90, step: 5) {
                        LabeledContent("Длительность обеда", value: minText(plan.lunchMinutes))
                    }
                }
            }

            Section("Получится") {
                if preview.isEmpty {
                    Text("Ничего не помещается в сутки").foregroundStyle(.secondary)
                } else {
                    ForEach(preview.sortedNumbers, id: \.self) { n in
                        if let s = preview[n] {
                            LabeledContent("\(n) пара", value: slotRange(s))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Автозаполнение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Применить") { apply() }.disabled(preview.isEmpty)
            }
        }
        .onChange(of: plan.count) { _, n in
            if plan.lunchAfter >= n { plan.lunchAfter = 0 }
        }
    }

    private func apply() {
        let store = self.store
        let key = self.key
        let old = store.settings.bell(key)
        store.setBellProfile(key, preview)
        Haptics.success()
        close()
        toaster.show("Звонки заполнены") { store.setBellProfile(key, old) }
    }
}

// MARK: - Звонки дня (из расписания)

/// Шторка «Звонки» для открытой даты: время пар этого дня и переход к настройке.
struct DayBellsSheet: View {
    @Environment(AppStore.self) private var store
    let date: Date
    let close: () -> Void

    private var key: String { bellKey(for: date) }
    private var profile: BellProfile { store.settings.bell(key) }
    private var lessons: [Int] { store.cachedSchedule(on: date)?.slots.map { $0.number } ?? [] }

    var body: some View {
        List {
            Section {
                if profile.isEmpty {
                    ContentUnavailableView("Звонки не заданы", systemImage: "bell.slash",
                                           description: Text("Выберите готовое расписание или введите время пар."))
                } else {
                    ForEach(profile.sortedNumbers, id: \.self) { n in
                        if let s = profile[n] {
                            HStack(spacing: 12) {
                                NumberBadge(text: "\(n)", color: lessons.contains(n) ? .accentColor : .gray, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(slotRange(s)).font(.body.weight(.semibold)).monospacedDigit()
                                    if s.hasBreak {
                                        Text("\(halvesText(s)) · \(innerBreakWord(s)) \(shortRange(s.breakStart ?? 0, s.breakEnd ?? 0))")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if let gap = gapLabel(profile, n) {
                                Label(gap, systemImage: profile.isLunchAfter(n) ? "fork.knife" : "cup.and.saucer")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            } header: {
                Text(bellTitle(key))
            }

            Section {
                NavigationLink {
                    BellsView(initialKey: key)
                } label: {
                    Label("Настроить звонки", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle("Звонки")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(dayCaption(date))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Готово") { close() } }
        }
    }
}
