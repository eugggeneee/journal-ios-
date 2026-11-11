import SwiftUI

// MARK: - Один день

/// Загружает расписание дня и показывает нужное состояние.
struct DayView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ScheduleRepo.self) private var repo

    let date: Date
    let tick: Int

    @State private var state: DayState?
    @State private var initialTick: Int

    init(date: Date, tick: Int) {
        self.date = date
        self.tick = tick
        _initialTick = State(initialValue: tick)
    }

    private var taskKey: String { "\(ymd(date))|\(store.settings.group)|\(tick)" }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load(force: true) }
        .task(id: taskKey) { await load(force: tick != initialTick) }
    }

    @ViewBuilder
    private var content: some View {
        if let st = state {
            switch st.status {
            case .ok:
                if let sched = st.schedule, !sched.slots.isEmpty {
                    TodayAware(date: date) { now in
                        DayContent(date: date, schedule: sched, note: st.note, now: now)
                    }
                } else {
                    emptyState(icon: "checkmark.circle", title: "Пар нет", text: "На этот день занятий в расписании нет.")
                }
            case .sunday:
                emptyState(icon: "sun.max", title: "Воскресенье", text: "Выходной день — занятий нет.")
            case .notPublished:
                emptyState(icon: "clock.badge.questionmark", title: "Расписание не опубликовано",
                           text: "На сайте колледжа этого дня ещё нет. Обычно расписание появляется накануне.")
            case .noGroup:
                emptyState(icon: "checkmark.circle", title: "Пар нет",
                           text: "Для группы \(store.settings.group) на этот день занятий нет.")
            case .offline:
                emptyState(icon: "wifi.slash", title: "Нет подключения",
                           text: st.note ?? "Не удалось загрузить расписание. Потяните вниз, чтобы повторить.", retry: true)
            case .error:
                emptyState(icon: "exclamationmark.triangle", title: "Не удалось загрузить",
                           text: st.note ?? "Сайт колледжа ответил с ошибкой. Попробуйте позже.", retry: true)
            }
        } else {
            VStack { ProgressView() }
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func emptyState(icon: String, title: String, text: String, retry: Bool = false) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(text)
            } actions: {
                if retry {
                    Button("Повторить") { Task { await load(force: true) } }
                        .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320)

            let marks = store.marks(on: date)
            if !marks.isEmpty {
                VStack(spacing: 8) {
                    ForEach(marks) { m in
                        Button {
                            router.present(.mark(date: date, lesson: m.lesson > 0 ? m.lesson : nil, edit: m))
                        } label: {
                            Label(m.wholeDay ? m.label : "\(m.lesson) пара · \(m.label)", systemImage: "flag.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(markColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(markColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 24)
    }

    private func load(force: Bool) async {
        let result = await repo.load(date, force: force)
        if Task.isCancelled { return }
        withAnimation(.smooth) { state = result }
    }
}

/// Для сегодняшнего дня обновляет «сейчас» раз в полминуты.
private struct TodayAware<Content: View>: View {
    let date: Date
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if sameDay(date, Date()) {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in content(DemoMode.clock(ctx.date)) }
        } else {
            content(Date())
        }
    }
}

// MARK: - Лента дат

private struct DateStrip: View {
    let base: Date
    let back: Int
    let total: Int
    @Binding var index: Int?
    let onGroupTap: () -> Void
    let group: String

    private func date(_ i: Int) -> Date { addDays(base, i - back) }

    var body: some View {
        let current = index ?? back
        VStack(spacing: 6) {
            HStack {
                Text(monthYear(date(current)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                Spacer()
                Button(action: onGroupTap) {
                    Label("Группа \(group)", systemImage: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(0..<total, id: \.self) { i in
                            chip(i, selected: i == current)
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(current, anchor: .center) }
                .onChange(of: index) { _, new in
                    guard let new = new else { return }
                    withAnimation(.smooth) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func chip(_ i: Int, selected: Bool) -> some View {
        let d = date(i)
        let isToday = sameDay(d, Date())
        Button {
            withAnimation(.smooth) { index = i }
        } label: {
            VStack(spacing: 3) {
                Text(weekdayShort(d))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                Text("\(dayOf(d))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(selected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                Circle()
                    .fill(isToday ? (selected ? Color.white : Color.accentColor) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 48, height: 68)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor.gradient)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(longDate(d))\(isToday ? ", сегодня" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Экран

struct SchedulePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ScheduleRepo.self) private var repo
    @Environment(Toaster.self) private var toaster
    @Environment(\.scenePhase) private var scenePhase

    private static let back = 60
    private static let forward = 240
    private var total: Int { SchedulePage.back + SchedulePage.forward + 1 }

    @State private var base = today()
    @State private var index: Int? = SchedulePage.back + DemoMode.startOffset
    @State private var tick = 0

    private var selectedDate: Date { addDays(base, (index ?? SchedulePage.back) - SchedulePage.back) }
    private var isToday: Bool { sameDay(selectedDate, today()) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DateStrip(base: base, back: SchedulePage.back, total: total, index: $index,
                          onGroupTap: { router.present(.group) }, group: store.settings.group)
                pager
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(relativeDay(selectedDate))
            .navigationSubtitle(fullDate(selectedDate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Сегодня") { goToday() }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        router.present(.datePicker(selected: selectedDate, onPick: { picked in go(to: picked) }))
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Выбрать дату")

                    Menu {
                        Button { router.present(.grade(edit: nil, subject: nil, date: selectedDate)) } label: {
                            Label("Оценка", systemImage: "star")
                        }
                        Button { router.present(.absenceQuick(date: selectedDate, lesson: nil)) } label: {
                            Label("Пропуск", systemImage: "calendar.badge.minus")
                        }
                        Button { router.present(.mark(date: selectedDate, lesson: nil, edit: nil)) } label: {
                            Label("Пометка", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить")

                    Menu {
                        Button { router.present(.bells(date: selectedDate)) } label: {
                            Label("Звонки", systemImage: "bell")
                        }
                        Button { refresh() } label: {
                            Label("Обновить расписание", systemImage: "arrow.clockwise")
                        }
                        Button { router.present(.group) } label: {
                            Label("Сменить группу", systemImage: "person.2")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Ещё")
                }
            }
        }
        .toastHost()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resetIfDayChanged() }
        }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<total, id: \.self) { i in
                    DayView(date: addDays(base, i - SchedulePage.back), tick: tick)
                        .containerRelativeFrame(.horizontal)
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $index)
        .scrollIndicators(.hidden)
        .onChange(of: index) { _, _ in Haptics.selection() }
    }

    private func goToday() {
        Haptics.light()
        resetIfDayChanged()
        withAnimation(.smooth) { index = SchedulePage.back }
    }

    /// Переходит к дате, а если она вне диапазона ленты — пересобирает ленту вокруг неё.
    private func go(to date: Date) {
        let offset = dayDiff(date, base)
        let i = offset + SchedulePage.back
        if i >= 0 && i < total {
            withAnimation(.smooth) { index = i }
        } else {
            base = dateOnly(date)
            index = SchedulePage.back
        }
    }

    /// Если наступил новый день, лента заново строится вокруг сегодняшней даты.
    private func resetIfDayChanged() {
        if !sameDay(base, today()) {
            base = today()
            index = SchedulePage.back
        }
    }

    private func refresh() {
        Haptics.light()
        tick += 1
        Task { await repo.prefetch(force: true, respectSetting: false) }
        toaster.show("Обновляем расписание…")
    }
}
