import Foundation

/// Какое расписание звонков действует в день [date].
func bellKey(for date: Date) -> String { isSaturday(date) ? kBellSat : kBellWeek }

func bellTitle(_ key: String) -> String { key == kBellSat ? "Суббота" : "Будни" }

/// Параметры быстрого заполнения звонков.
struct BellPlan {
    var firstStart: Int = 8 * 60 + 30
    var pairMinutes: Int = 90
    var breakMinutes: Int = 10
    var count: Int = kMaxPairs
    var lunchAfter: Int = 0
    var lunchMinutes: Int = 30
    /// Перерыв внутри пары, минут (0 — без перерыва); ставится посередине пары.
    var innerBreak: Int = 0
}

/// Раскладывает пары подряд: пара, перерыв, пара… с обедом после выбранной пары.
func generateBells(_ p: BellPlan) -> BellProfile {
    var t = p.firstStart
    var slots: [Int: BellSlot] = [:]
    var n = 1
    while n <= p.count && n <= kMaxPairs {
        let end = t + p.pairMinutes
        if end > 24 * 60 { break }
        var bs: Int?
        var be: Int?
        if p.innerBreak > 0 && p.innerBreak < p.pairMinutes - 2 {
            let start = t + (p.pairMinutes - p.innerBreak) / 2
            bs = start
            be = start + p.innerBreak
        }
        slots[n] = BellSlot(start: t, end: end, breakStart: bs, breakEnd: be)
        t = end + (n == p.lunchAfter ? p.lunchMinutes : p.breakMinutes)
        n += 1
    }
    let lunch = (p.lunchAfter >= 1 && p.lunchAfter < slots.count) ? p.lunchAfter : 0
    return BellProfile(slots: slots, lunchAfter: lunch)
}

/// Подпись перерыва после пары [n]: «Обед 40 мин» или «Перерыв 10 мин» (nil — следующей пары нет).
func gapLabel(_ p: BellProfile, _ n: Int) -> String? {
    guard let gap = p.gapAfter(n), gap > 0 else { return nil }
    return "\(p.isLunchAfter(n) ? "Обед" : "Перерыв") \(minText(gap))"
}

/// Как называть перерыв внутри пары: «обед» (от 20 минут) или «перерыв».
func innerBreakWord(_ s: BellSlot) -> String { s.lunchInside ? "обед" : "перерыв" }

/// «45 + 45 мин» или «90 мин» — из чего состоит пара.
func halvesText(_ s: BellSlot) -> String {
    s.hasBreak ? "\(s.firstHalf) + \(s.secondHalf) мин" : minText(s.minutes)
}

/// «08:30 – 10:00».
func slotRange(_ s: BellSlot) -> String { "\(fmtMin(s.start)) – \(fmtMin(s.end))" }

/// «09:05–09:15» — короткая запись промежутка времени (минуты от полуночи).
func shortRange(_ from: Int, _ to: Int) -> String { "\(fmtMin(from))–\(fmtMin(to))" }

// MARK: - Готовые расписания звонков

struct BellPreset: Identifiable {
    let id: String
    let key: String
    let title: String
    let subtitle: String
    let profile: BellProfile
}

private func m(_ h: Int, _ min: Int) -> Int { h * 60 + min }

/// Пара из двух уроков и перерыва между ними: (h1:m1–h2:m2), перерыв, (h3:m3–h4:m4).
private func pair(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int, _ h3: Int, _ m3: Int, _ h4: Int, _ m4: Int) -> BellSlot {
    BellSlot(start: m(h1, m1), end: m(h4, m4), breakStart: m(h2, m2), breakEnd: m(h3, m3))
}

/// Расписания звонков МГТЭК: два варианта для пн–пт и один для субботы.
let kBellPresets: [BellPreset] = [
    BellPreset(
        id: "week1", key: kBellWeek, title: "Расписание 1",
        subtitle: "Пн–Пт · 7 пар · обед 11:50–12:20 перед 3 парой",
        profile: BellProfile(slots: [
            1: pair(8, 20, 9, 5, 9, 15, 10, 0),
            2: pair(10, 10, 10, 55, 11, 5, 11, 50),
            3: pair(12, 20, 13, 5, 13, 15, 14, 0),
            4: pair(14, 10, 14, 55, 15, 0, 15, 45),
            5: pair(15, 55, 16, 40, 16, 45, 17, 30),
            6: pair(17, 40, 18, 25, 18, 30, 19, 15),
            7: pair(19, 25, 20, 10, 20, 15, 21, 0),
        ], lunchAfter: 2)
    ),
    BellPreset(
        id: "week2", key: kBellWeek, title: "Расписание 2",
        subtitle: "Пн–Пт · 7 пар · обед 12:45–13:15 посреди 3 пары",
        profile: BellProfile(slots: [
            1: pair(8, 20, 9, 5, 9, 15, 10, 0),
            2: pair(10, 10, 10, 55, 11, 5, 11, 50),
            3: pair(12, 0, 12, 45, 13, 15, 14, 0),
            4: pair(14, 10, 14, 55, 15, 0, 15, 45),
            5: pair(15, 55, 16, 40, 16, 45, 17, 30),
            6: pair(17, 40, 18, 25, 18, 30, 19, 15),
            7: pair(19, 25, 20, 10, 20, 15, 21, 0),
        ])
    ),
    BellPreset(
        id: "sat", key: kBellSat, title: "Расписание 3",
        subtitle: "Суббота · 6 пар · для всех групп",
        profile: BellProfile(slots: [
            1: pair(8, 20, 9, 5, 9, 10, 9, 55),
            2: pair(10, 5, 10, 50, 10, 55, 11, 40),
            3: pair(11, 50, 12, 35, 12, 40, 13, 25),
            4: pair(13, 35, 14, 20, 14, 25, 15, 10),
            5: pair(15, 20, 16, 5, 16, 10, 16, 55),
            6: pair(17, 5, 17, 50, 17, 55, 18, 40),
        ])
    ),
]

// MARK: - Состояние дня

/// Что происходит в расписании дня в данную минуту.
enum DayPhase {
    case none        // звонков для пар дня нет
    case before      // занятия ещё не начались
    case lesson      // идёт пара
    case innerBreak  // перерыв внутри пары
    case gap         // перерыв (обед или окно) между парами
    case after       // занятия закончились
}

/// Состояние дня: фаза, нужная пара, сколько минут осталось и какая доля уже прошла (0…1).
struct DayClock {
    var phase: DayPhase
    var pair: Int? = nil
    var next: Int? = nil
    var left: Int = 0
    var progress: Double = 0
}

/// Состояние дня в минуту [minute]; [lessons] — номера пар, которые есть в расписании этого дня.
func dayClock(_ profile: BellProfile, _ lessons: [Int], _ minute: Int) -> DayClock {
    let nums = lessons.filter { profile[$0] != nil }.sorted()
    guard let firstNum = nums.first, let lastNum = nums.last,
          let first = profile[firstNum], let last = profile[lastNum] else {
        return DayClock(phase: .none)
    }
    if minute < first.start {
        return DayClock(phase: .before, next: firstNum, left: first.start - minute)
    }
    if minute >= last.end { return DayClock(phase: .after, pair: lastNum) }
    for i in 0..<nums.count {
        let n = nums[i]
        guard let s = profile[n] else { continue }
        if minute >= s.start && minute < s.end {
            if let bs = s.breakStart, let be = s.breakEnd, minute >= bs && minute < be {
                return DayClock(phase: .innerBreak, pair: n, left: be - minute,
                                progress: Double(minute - bs) / Double(max(1, s.breakMinutes)))
            }
            return DayClock(phase: .lesson, pair: n, left: s.end - minute,
                            progress: Double(minute - s.start) / Double(max(1, s.minutes)))
        }
        if i + 1 < nums.count, let next = profile[nums[i + 1]], minute >= s.end && minute < next.start {
            return DayClock(phase: .gap, pair: n, next: nums[i + 1], left: next.start - minute,
                            progress: Double(minute - s.end) / Double(max(1, next.start - s.end)))
        }
    }
    return DayClock(phase: .none)
}

/// Подпись промежутка между двумя соседними парами дня: «Перерыв 10 мин», «Обед 40 мин»
/// или «Окно 1 ч 40 мин», если между парами в расписании дня нет одной или нескольких пар.
func gapBetween(_ p: BellProfile, _ from: Int, _ to: Int) -> String? {
    let a = p[from]
    let b = p[to]
    let skipped = to - from > 1
    var minutes: Int?
    if let a = a, let b = b { minutes = b.start - a.end }
    if let mins = minutes, mins <= 0 { return nil }
    if skipped {
        let span = minutes.map { " \(spanText($0))" } ?? ""
        return "Окно\(span)"
    }
    guard let mins = minutes else { return nil }
    return "\(p.isLunchAfter(from) ? "Обед" : "Перерыв") \(spanText(mins))"
}
