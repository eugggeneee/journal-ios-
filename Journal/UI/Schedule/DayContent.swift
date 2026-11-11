import SwiftUI

// MARK: - Рельса таймлайна

/// Вертикальная линия с узлом: показывает, сколько времени дня уже прошло.
private struct Rail: View {
    var hasTop: Bool
    var hasBottom: Bool
    var topFill: Double
    var bottomFill: Double
    var node: NodeKind
    var nodeY: CGFloat = 37

    enum NodeKind { case none, future, done, current }

    private struct Segment {
        let from: CGFloat
        let to: CGFloat
        let color: Color
    }

    private func segments(height: CGFloat) -> [Segment] {
        let track = Color(.systemFill)
        let fill = Color.accentColor
        var out: [Segment] = []
        if node == .none {
            out.append(Segment(from: 0, to: height, color: track))
            if topFill > 0 { out.append(Segment(from: 0, to: height * CGFloat(min(1, topFill)), color: fill)) }
            return out
        }
        if hasTop {
            out.append(Segment(from: 0, to: nodeY, color: track))
            if topFill > 0 { out.append(Segment(from: 0, to: nodeY * CGFloat(min(1, topFill)), color: fill)) }
        }
        if hasBottom {
            out.append(Segment(from: nodeY, to: height, color: track))
            if bottomFill > 0 {
                out.append(Segment(from: nodeY, to: nodeY + (height - nodeY) * CGFloat(min(1, bottomFill)), color: fill))
            }
        }
        return out
    }

    var body: some View {
        Canvas { ctx, size in
            let x = size.width / 2
            for seg in segments(height: size.height) where seg.to > seg.from {
                var p = Path()
                p.move(to: CGPoint(x: x, y: seg.from))
                p.addLine(to: CGPoint(x: x, y: seg.to))
                ctx.stroke(p, with: .color(seg.color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if node == .none { return }
            let fill = Color.accentColor
            let r: CGFloat = node == .current ? 8 : 6
            let rect = CGRect(x: x - r, y: nodeY - r, width: r * 2, height: r * 2)
            switch node {
            case .done:
                ctx.fill(Path(ellipseIn: rect), with: .color(fill))
            case .current:
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(fill.opacity(0.25)))
                ctx.fill(Path(ellipseIn: rect), with: .color(fill))
            default:
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(.systemBackground)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(Color(.systemGray3)), lineWidth: 2)
            }
        }
        .frame(width: 26)
        .accessibilityHidden(true)
    }
}

// MARK: - Содержимое дня

private enum TimelineItem: Identifiable {
    case lesson(LessonSlot)
    case gap(String, from: Int, to: Int)

    var id: String {
        switch self {
        case .lesson(let s): return "l\(s.number)"
        case .gap(_, let a, let b): return "g\(a)-\(b)"
        }
    }
}

struct DayContent: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Toaster.self) private var toaster

    let date: Date
    let schedule: DaySchedule
    let note: String?
    let now: Date

    private var isToday: Bool { sameDay(date, now) }
    private var isPast: Bool { dayDiff(date, now) < 0 }
    private var profile: BellProfile { store.bellProfile(for: date) }
    private var minute: Int { minuteOfDay(now) }
    private var slots: [LessonSlot] { schedule.slots }

    private var clock: DayClock {
        isToday ? dayClock(profile, slots.map { $0.number }, minute) : DayClock(phase: .none)
    }

    private var items: [TimelineItem] {
        var out: [TimelineItem] = []
        for (i, s) in slots.enumerated() {
            if i > 0, let g = gapBetween(profile, slots[i - 1].number, s.number) {
                out.append(.gap(g, from: slots[i - 1].number, to: s.number))
            }
            out.append(.lesson(s))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let note = note {
                Label(note, systemImage: "wifi.slash")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            summary

            if isToday, clock.phase != .none, clock.phase != .after {
                NowCard(clock: clock, profile: profile, slots: slots, store: store)
            }

            let wholeDayMarks = store.marks(on: date).filter { $0.wholeDay }
            if !wholeDayMarks.isEmpty {
                wholeDayMarksView(wholeDayMarks)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .lesson(let s):
                        lessonRow(s, isFirst: index == 0, isLast: index == items.count - 1)
                    case .gap(let text, let from, let to):
                        gapRow(text, from: from, to: to)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: Сводка

    private var summary: some View {
        let hoursTotal = slots.count * 2
        let missed = store.absences(on: date).filter { !$0.excused }.reduce(0) { $0 + $1.hours }
        let allMarked = slots.allSatisfy { store.absence(on: date, lesson: $0.number) != nil }
        let first = slots.first.flatMap { profile[$0.number] }
        let last = slots.last.flatMap { profile[$0.number] }
        var sub = "\(hoursText(hoursTotal))"
        if let f = first, let l = last { sub = "\(fmtMin(f.start)) – \(fmtMin(l.end)) · \(sub)" }
        if isToday && clock.phase == .after { sub = "Занятия закончились · \(sub)" }

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pairsText(slots.count)).font(.title2.weight(.bold))
                Text(sub).font(.subheadline).foregroundStyle(.secondary)
                if missed > 0 {
                    Pill(text: "Пропущено \(missed) ч", systemImage: "calendar.badge.minus", color: .red)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button {
                    DayActions.toggleShortDay(store: store, toaster: toaster, date: date)
                } label: {
                    let on = store.mark(on: date, lesson: 0)?.label == kShortDayMark
                    Label(on ? "Снять «Сокращённый день»" : "Сокращённый день", systemImage: "clock.badge.checkmark")
                }
                Button {
                    router.present(.mark(date: date, lesson: nil, edit: nil))
                } label: {
                    Label("Пометка на день", systemImage: "flag")
                }
            } label: {
                Label(allMarked ? "Снять" : "Весь день", systemImage: allMarked ? "arrow.uturn.backward" : "calendar.badge.minus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)
            } primaryAction: {
                DayActions.toggleWholeDay(store: store, toaster: toaster, router: router, date: date, slots: slots)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(allMarked ? "Снять отметки пропусков дня" : "Отметить пропуск всего дня")
        }
        .padding(.horizontal, 4)
    }

    private func wholeDayMarksView(_ marks: [DayMark]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(marks) { m in
                Button {
                    router.present(.mark(date: date, lesson: nil, edit: m))
                } label: {
                    Label(m.label, systemImage: "flag.fill")
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
    }

    // MARK: Строки

    private func lessonProgress(_ s: LessonSlot) -> (top: Double, bottom: Double, node: Rail.NodeKind) {
        if isPast { return (1, 1, .done) }
        if !isToday { return (0, 0, .future) }
        guard let b = profile[s.number] else { return (0, 0, .future) }
        let m = minute
        if m >= b.end { return (1, 1, .done) }
        if m >= b.start { return (1, Double(m - b.start) / Double(max(1, b.minutes)), .current) }
        return (0, 0, .future)
    }

    private func gapFill(from: Int, to: Int) -> Double {
        if isPast { return 1 }
        if !isToday { return 0 }
        guard let a = profile[from], let b = profile[to] else { return 0 }
        let m = minute
        if m >= b.start { return 1 }
        if m <= a.end { return 0 }
        return Double(m - a.end) / Double(max(1, b.start - a.end))
    }

    private func lessonRow(_ s: LessonSlot, isFirst: Bool, isLast: Bool) -> some View {
        let p = lessonProgress(s)
        let bell = profile[s.number]
        let absence = store.absence(on: date, lesson: s.number)
        let mark = store.mark(on: date, lesson: s.number)
        let current = p.node == .current
        let finished = p.node == .done && isToday

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                if let b = bell {
                    Text(fmtMin(b.start)).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                    Text(fmtMin(b.end)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
            .padding(.top, 14)

            Color.clear.frame(width: 26)

            card(s, absence: absence, mark: mark, bell: bell, current: current)
                .padding(.vertical, 4)
        }
        .background(alignment: .topLeading) {
            Rail(hasTop: !isFirst, hasBottom: !isLast, topFill: p.top, bottomFill: p.bottom, node: p.node)
                .padding(.leading, 50)
        }
        .opacity(finished ? 0.6 : 1)
        .contextMenu {
            Button {
                DayActions.toggleLessonAbsence(store: store, toaster: toaster, router: router, date: date, slot: s)
            } label: {
                Label(absence == nil ? "Отметить пропуск" : "Снять пропуск",
                      systemImage: absence == nil ? "calendar.badge.minus" : "xmark.circle")
            }
            Button {
                router.present(.grade(edit: nil, subject: s.subject, date: date))
            } label: {
                Label("Добавить оценку", systemImage: "plus.circle")
            }
            Button {
                router.present(.mark(date: date, lesson: s.number, edit: mark))
            } label: {
                Label(mark == nil ? "Добавить пометку" : "Изменить пометку", systemImage: "flag")
            }
        }
    }

    private func card(_ s: LessonSlot, absence: Absence?, mark: DayMark?, bell: BellSlot?, current: Bool) -> some View {
        let tint: Color? = current ? .accentColor : (absence.map { absenceColor(excused: $0.excused) })
        return HStack(spacing: 0) {
            Button {
                router.present(.lesson(date: date, slot: s))
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    NumberBadge(text: "\(s.number)", color: current ? .accentColor : .gray)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.subjects.map(store.subjectName).joined(separator: " / "))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        detailLine(s)
                        if let b = bell, b.hasBreak {
                            Text("\(innerBreakWord(b).capitalizedFirst) \(shortRange(b.breakStart ?? 0, b.breakEnd ?? 0))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let m = mark {
                            Pill(text: m.label, systemImage: "flag.fill", color: markColor)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            absenceButton(s, absence: absence)
        }
        .padding(14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
                if let tint = tint {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.opacity(0.12))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func detailLine(_ s: LessonSlot) -> some View {
        if s.entries.count == 1, let e = s.entries.first {
            let parts = [e.room.isEmpty ? nil : "ауд. \(e.room)", e.teacher.isEmpty ? nil : e.teacher].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        } else if s.entries.count > 1 {
            Text("Подгруппы: \(s.entries.count)").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func absenceButton(_ s: LessonSlot, absence: Absence?) -> some View {
        Button {
            DayActions.toggleLessonAbsence(store: store, toaster: toaster, router: router, date: date, slot: s)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: absence == nil ? "circle" : (absence!.excused ? "checkmark.circle.fill" : "xmark.circle.fill"))
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(absence.map { absenceColor(excused: $0.excused) } ?? Color(.systemGray3))
                if let a = absence {
                    Text("\(a.hours) ч").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(absence == nil ? "Отметить пропуск \(s.number) пары" : "Снять пропуск \(s.number) пары")
    }

    private func gapRow(_ text: String, from: Int, to: Int) -> some View {
        let fill = gapFill(from: from, to: to)
        return HStack(alignment: .center, spacing: 8) {
            Color.clear.frame(width: 42)
            Color.clear.frame(width: 26)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
        .background(alignment: .topLeading) {
            Rail(hasTop: true, hasBottom: true, topFill: fill, bottomFill: 0, node: .none)
                .padding(.leading, 50)
        }
        .opacity(isToday && fill >= 1 ? 0.6 : 1)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Карточка «Сейчас»

struct NowCard: View {
    let clock: DayClock
    let profile: BellProfile
    let slots: [LessonSlot]
    let store: AppStore

    private func name(_ n: Int?) -> String {
        guard let n = n, let s = slots.first(where: { $0.number == n }) else { return "" }
        return s.subjects.map(store.subjectName).joined(separator: " / ")
    }

    var body: some View {
        let t = texts
        HeroCard(tint: .accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                Text(t.overline).font(.footnote.weight(.bold)).foregroundStyle(Color.accentColor).textCase(.uppercase)
                Text(t.title).font(.title3.weight(.bold)).lineLimit(2)
                HStack(alignment: .firstTextBaseline) {
                    Text(t.left).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(t.leftCaption).font(.subheadline).foregroundStyle(.secondary)
                }
                if clock.phase != .before {
                    ProgressBar(value: clock.progress, color: .accentColor, height: 8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var texts: (overline: String, title: String, left: String, leftCaption: String) {
        let left = spanText(max(1, clock.left))
        switch clock.phase {
        case .before:
            return ("Скоро начало", "\(clock.next ?? 1) пара · \(name(clock.next))", left, "до начала занятий")
        case .lesson:
            return ("Идёт \(clock.pair ?? 1) пара", name(clock.pair), left, "до конца пары")
        case .innerBreak:
            let word = profile[clock.pair ?? 0].map { innerBreakWord($0) } ?? "перерыв"
            return ("Внутри \(clock.pair ?? 1) пары", name(clock.pair), left, "до конца \(word)а")
        case .gap:
            let lunch = profile.isLunchAfter(clock.pair ?? 0)
            return (lunch ? "Обед" : "Перерыв", "Дальше: \(clock.next ?? 1) пара · \(name(clock.next))", left, "до начала")
        default:
            return ("", "", "", "")
        }
    }
}
