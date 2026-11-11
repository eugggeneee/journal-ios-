import Foundation

// MARK: - Разбор JSON (устойчивый к мусору, как в исходном приложении)

enum J {
    static func int(_ v: Any?, _ fallback: Int) -> Int {
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return fallback }
            return n.intValue
        }
        if let s = v as? String, let i = Int(s) { return i }
        return fallback
    }

    static func str(_ v: Any?) -> String {
        guard let v = v, !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        return "\(v)"
    }

    /// Строго логическое значение: только true или false, числа не считаются.
    static func bool(_ v: Any?) -> Bool? {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    static func dict(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
    static func list(_ v: Any?) -> [Any] { (v as? [Any]) ?? [] }
}

private var idCounter = 0

func newId() -> String {
    idCounter += 1
    return "\(Int(Date().timeIntervalSince1970 * 1_000_000))-\(idCounter)"
}

// MARK: - Расписание

/// Одна строка расписания: предмет, аудитория, преподаватель.
struct LessonEntry: Hashable {
    var subject: String
    var room: String
    var teacher: String

    var json: [String: Any] { ["s": subject, "r": room, "t": teacher] }

    init(subject: String, room: String, teacher: String) {
        self.subject = subject
        self.room = room
        self.teacher = teacher
    }

    init(json j: [String: Any]) {
        subject = J.str(j["s"])
        room = J.str(j["r"])
        teacher = J.str(j["t"])
    }
}

/// Пара №N. Несколько записей — подгруппы (разные аудитории и преподаватели).
struct LessonSlot: Hashable, Identifiable {
    var number: Int
    var entries: [LessonEntry]

    var id: Int { number }
    var subject: String { entries.first?.subject ?? "" }

    var subjects: [String] {
        var out: [String] = []
        for e in entries where !out.contains(e.subject) { out.append(e.subject) }
        return out
    }

    init(number: Int, entries: [LessonEntry]) {
        self.number = number
        self.entries = entries
    }

    init(json j: [String: Any]) {
        number = J.int(j["n"], 0)
        entries = J.list(j["e"]).compactMap { J.dict($0) }.map { LessonEntry(json: $0) }
    }

    var json: [String: Any] { ["n": number, "e": entries.map { $0.json }] }
}

/// Расписание группы на один день.
struct DaySchedule {
    var date: Date
    var group: String
    var slots: [LessonSlot]
    var fetchedAt: Date

    var json: [String: Any] {
        [
            "d": ymd(date),
            "g": group,
            "f": Int(fetchedAt.timeIntervalSince1970 * 1000),
            "slots": slots.map { $0.json },
        ]
    }

    init(date: Date, group: String, slots: [LessonSlot], fetchedAt: Date) {
        self.date = date
        self.group = group
        self.slots = slots
        self.fetchedAt = fetchedAt
    }

    init?(json raw: Any?) {
        guard let j = J.dict(raw), let d = parseYmd(J.str(j["d"])) else { return nil }
        date = d
        group = J.str(j["g"])
        fetchedAt = Date(timeIntervalSince1970: Double(J.int(j["f"], 0)) / 1000)
        slots = J.list(j["slots"]).compactMap { J.dict($0) }.map { LessonSlot(json: $0) }
    }
}

// MARK: - Оценки

/// Оценка по 10-балльной шкале.
struct Grade: Identifiable, Hashable {
    var id: String
    var subject: String
    var value: Int
    var date: Date
    var kind: String = ""
    var note: String = ""

    var json: [String: Any] {
        ["id": id, "s": subject, "v": value, "d": ymd(date), "k": kind, "n": note]
    }

    init(id: String, subject: String, value: Int, date: Date, kind: String = "", note: String = "") {
        self.id = id
        self.subject = subject
        self.value = value
        self.date = date
        self.kind = kind
        self.note = note
    }

    init?(json raw: Any?) {
        guard let j = J.dict(raw), let d = parseYmd(J.str(j["d"])) else { return nil }
        let v = J.int(j["v"], 0)
        guard v >= 1, v <= 10 else { return nil }
        let rawId = J.str(j["id"])
        id = rawId.isEmpty ? newId() : rawId
        subject = J.str(j["s"])
        value = v
        date = d
        kind = J.str(j["k"])
        note = J.str(j["n"])
    }
}

// MARK: - Пропуски

/// Пропуск: 1 или 2 часа (пара — 2 академических часа).
struct Absence: Identifiable, Hashable {
    var id: String
    var date: Date
    var lesson: Int // номер пары; 0 — не указан
    var subject: String
    var hours: Int // 1 или 2
    var excused: Bool = false
    var note: String = ""

    var json: [String: Any] {
        ["id": id, "d": ymd(date), "l": lesson, "s": subject, "h": hours, "e": excused, "n": note]
    }

    init(id: String, date: Date, lesson: Int, subject: String, hours: Int, excused: Bool = false, note: String = "") {
        self.id = id
        self.date = date
        self.lesson = lesson
        self.subject = subject
        self.hours = hours
        self.excused = excused
        self.note = note
    }

    init?(json raw: Any?) {
        guard let j = J.dict(raw), let d = parseYmd(J.str(j["d"])) else { return nil }
        let rawId = J.str(j["id"])
        id = rawId.isEmpty ? newId() : rawId
        date = d
        lesson = J.int(j["l"], 0)
        subject = J.str(j["s"])
        hours = J.int(j["h"], 2) == 1 ? 1 : 2
        excused = J.bool(j["e"]) ?? false
        note = J.str(j["n"])
    }
}

// MARK: - Звонки

let kBellWeek = "week"
let kBellSat = "sat"
let kBellKeys = [kBellWeek, kBellSat]

/// Максимальное число пар в расписании звонков.
let kMaxPairs = 7

/// Время одной пары (минуты от полуночи). Внутри пары может быть перерыв.
struct BellSlot: Hashable {
    var start: Int
    var end: Int
    var breakStart: Int?
    var breakEnd: Int?

    init(start: Int, end: Int, breakStart: Int? = nil, breakEnd: Int? = nil) {
        self.start = start
        self.end = end
        self.breakStart = breakStart
        self.breakEnd = breakEnd
    }

    var hasBreak: Bool { breakStart != nil && breakEnd != nil }
    var minutes: Int { end - start }
    var breakMinutes: Int {
        guard let bs = breakStart, let be = breakEnd else { return 0 }
        return be - bs
    }

    /// Перерыв внутри пары — это обед (от 20 минут).
    var lunchInside: Bool { hasBreak && breakMinutes >= 20 }

    /// Первая половина пары (до перерыва); без перерыва — вся пара.
    var firstHalf: Int {
        guard let bs = breakStart, hasBreak else { return minutes }
        return bs - start
    }

    /// Вторая половина пары (после перерыва); без перерыва — 0.
    var secondHalf: Int {
        guard let be = breakEnd, hasBreak else { return 0 }
        return end - be
    }

    /// Конец позже начала, перерыв целиком внутри пары.
    var valid: Bool {
        guard start >= 0, end <= 24 * 60, end > start else { return false }
        guard let bs = breakStart, let be = breakEnd else { return true }
        return bs > start && be > bs && be < end
    }

    func withoutBreak() -> BellSlot { BellSlot(start: start, end: end) }

    var json: [Int] { [start, end, breakStart ?? -1, breakEnd ?? -1] }

    init?(json raw: Any?) {
        guard let arr = raw as? [Any] else { return nil }
        let l = arr.map { J.int($0, -1) }
        guard l.count >= 2, l[0] >= 0, l[1] > l[0] else { return nil }
        let hasBreak = l.count >= 4 && l[2] >= 0 && l[3] > l[2]
        let slot = BellSlot(start: l[0], end: l[1], breakStart: hasBreak ? l[2] : nil, breakEnd: hasBreak ? l[3] : nil)
        self = slot.valid ? slot : slot.withoutBreak()
    }
}

/// Расписание звонков одного вида дней: время пар 1…7 и пара, после которой обед.
struct BellProfile: Equatable {
    var slots: [Int: BellSlot] = [:]
    /// Номер пары, после которой обед; 0 — обеда нет.
    var lunchAfter: Int = 0

    init(slots: [Int: BellSlot] = [:], lunchAfter: Int = 0) {
        self.slots = slots
        self.lunchAfter = lunchAfter
    }

    var isEmpty: Bool { slots.isEmpty }
    subscript(n: Int) -> BellSlot? { slots[n] }

    func withSlot(_ n: Int, _ slot: BellSlot?) -> BellProfile {
        var m = slots
        if let slot = slot { m[n] = slot } else { m.removeValue(forKey: n) }
        return BellProfile(slots: m, lunchAfter: lunchAfter)
    }

    func withLunch(_ n: Int) -> BellProfile { BellProfile(slots: slots, lunchAfter: n) }

    /// Те же пары и тот же обед (для подсветки применённого готового расписания).
    func sameAs(_ o: BellProfile) -> Bool { self == o }

    /// Номер следующей заданной пары после [n].
    func nextPair(_ n: Int) -> Int? {
        guard n < kMaxPairs else { return nil }
        for m in (n + 1)...kMaxPairs where slots[m] != nil { return m }
        return nil
    }

    /// Сколько минут перерыв между парой [n] и следующей заданной парой.
    func gapAfter(_ n: Int) -> Int? {
        guard let a = slots[n], let next = nextPair(n), let b = slots[next] else { return nil }
        return b.start - a.end
    }

    func isLunchAfter(_ n: Int) -> Bool { lunchAfter > 0 && lunchAfter == n }

    var sortedNumbers: [Int] { slots.keys.sorted() }

    var json: [String: Any] {
        var s: [String: Any] = [:]
        for (k, v) in slots { s["\(k)"] = v.json }
        return ["s": s, "l": lunchAfter]
    }

    init(json raw: Any?) {
        guard let j = J.dict(raw) else { self.init(); return }
        var out: [Int: BellSlot] = [:]
        for (key, value) in J.dict(j["s"]) ?? [:] {
            if let n = Int(key), n >= 1, n <= kMaxPairs, let slot = BellSlot(json: value) { out[n] = slot }
        }
        let lunch = J.int(j["l"], 0)
        self.init(slots: out, lunchAfter: (lunch >= 1 && lunch < kMaxPairs) ? lunch : 0)
    }

    /// Первая найденная проблема во времени пар (nil — всё в порядке).
    var problem: String? {
        let nums = sortedNumbers
        for i in 0..<nums.count {
            guard let slot = slots[nums[i]] else { continue }
            if !slot.valid { return "\(nums[i]) пара: проверьте время и перерыв внутри пары" }
            if i > 0, let prev = slots[nums[i - 1]], slot.start < prev.end {
                return "\(nums[i]) пара начинается раньше конца \(nums[i - 1])-й"
            }
        }
        return nil
    }
}

// MARK: - Пометки

/// Пометка к дате: «ОКР», «Зачёт», «Практика» или своя. lesson == 0 — на весь день.
struct DayMark: Identifiable, Hashable {
    var id: String
    var date: Date
    var lesson: Int
    var label: String

    var wholeDay: Bool { lesson <= 0 }

    var json: [String: Any] { ["id": id, "d": ymd(date), "l": lesson, "t": label] }

    init(id: String, date: Date, lesson: Int, label: String) {
        self.id = id
        self.date = date
        self.lesson = lesson
        self.label = label
    }

    init?(json raw: Any?) {
        guard let j = J.dict(raw), let d = parseYmd(J.str(j["d"])) else { return nil }
        let text = J.str(j["t"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let rawId = J.str(j["id"])
        id = rawId.isEmpty ? newId() : rawId
        date = d
        lesson = max(0, J.int(j["l"], 0))
        label = text
    }
}

/// Шаблон пометки на весь день.
let kShortDayMark = "Сокращённый день"

/// Готовые названия пометок.
let kMarkPresets = ["ОКР", "Зачёт", "Практика", kShortDayMark]

// MARK: - Настройки

struct Settings {
    var group: String = ""
    var extraSubjects: [String] = []
    var onboarded: Bool = false
    /// Сколько часов отмечать при быстром нажатии: 1 или 2.
    var absenceHours: Int = 2
    /// Подгружать расписание при запуске и возвращении в приложение.
    var autoRefresh: Bool = true
    /// Расписание звонков: «week» (пн–пт) и «sat» (суббота).
    var bells: [String: BellProfile] = [:]
    /// Конец 1-го семестра по учебным годам: «2026» → «2027-01-24».
    var semesterSplits: [String: String] = [:]
    /// Скрытые предупреждения о лимитах: ключ периода → самый высокий скрытый уровень.
    var dismissed: [String: Int] = [:]

    func bell(_ key: String) -> BellProfile { bells[key] ?? BellProfile() }

    /// Поля, которых в приложении больше нет (темы, анимации), пишутся значениями по умолчанию,
    /// чтобы копию можно было открыть и в прежней версии.
    var json: [String: Any] {
        var b: [String: Any] = [:]
        for (k, v) in bells { b[k] = v.json }
        return [
            "group": group,
            "extra": extraSubjects,
            "onb": onboarded,
            "theme": 0,
            "tc": "auto",
            "ah": absenceHours,
            "hap": true,
            "mot": 0,
            "dep": true,
            "auto": autoRefresh,
            "bells": b,
            "sem": semesterSplits,
            "dis": dismissed,
        ]
    }

    init() {}

    init(json raw: Any?) {
        guard let j = J.dict(raw) else { self.init(); return }
        self.init()
        let g = J.str(j["group"]).trimmingCharacters(in: .whitespacesAndNewlines)
        group = g
        extraSubjects = J.list(j["extra"]).map { J.str($0) }
        onboarded = J.bool(j["onb"]) ?? !g.isEmpty
        absenceHours = J.int(j["ah"], 2) == 1 ? 1 : 2
        autoRefresh = J.bool(j["auto"]) ?? true
        for (k, v) in J.dict(j["bells"]) ?? [:] where kBellKeys.contains(k) {
            bells[k] = BellProfile(json: v)
        }
        for (k, v) in J.dict(j["sem"]) ?? [:] {
            let s = J.str(v)
            if Int(k) != nil, parseYmd(s) != nil { semesterSplits[k] = s }
        }
        for (k, v) in J.dict(j["dis"]) ?? [:] { dismissed[k] = J.int(v, 0) }
    }
}
