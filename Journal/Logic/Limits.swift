import Foundation

/// Лимит часов без уважительной причины в месяц и когда показывать «лимит близко».
let kMonthLimit = 10
let kMonthWarnFrom = 7

/// Лимит часов без уважительной причины в семестр и когда показывать предупреждение.
let kSemesterLimit = 72
let kSemesterWarnFrom = 62

/// Уровень предупреждения; rawValue запоминается при скрытии карточки.
enum LimitLevel: Int {
    case ok = 0, near = 1, reached = 2
}

func limitLevel(_ hours: Int, warnFrom: Int, limit: Int) -> LimitLevel {
    if hours >= limit { return .reached }
    if hours >= warnFrom { return .near }
    return .ok
}

/// Часы без уважительной причины за период (обе даты включительно).
func unexcusedHoursBetween(_ list: [Absence], _ from: Date, _ to: Date) -> Int {
    let a = dateOnly(from)
    let b = dateOnly(to)
    var sum = 0
    for x in list where !x.excused {
        let d = dateOnly(x.date)
        if d >= a && d <= b { sum += x.hours }
    }
    return sum
}

/// Часы без уважительной причины в календарном месяце даты [now].
func monthUnexcusedHours(_ list: [Absence], _ now: Date) -> Int {
    unexcusedHoursBetween(list, makeDate(yearOf(now), monthOf(now), 1), monthEnd(now))
}

/// Семестр учебного года. Учебный год: с 1 сентября по 1 августа.
/// 1-й семестр заканчивается по кнопке в настройках — со дня нажатия сразу идёт 2-й, он длится до 1 августа.
struct Semester {
    /// Год начала учебного года (для 2026/27 это 2026).
    var year: Int
    /// 1 или 2.
    var number: Int
    var start: Date
    /// Последний день семестра (включительно).
    var end: Date
    /// Каникулы (2–31 августа): показан ближайший 1-й семестр, он ещё не начался.
    var upcoming: Bool = false

    var key: String { "\(year)-\(number)" }
    var title: String { "\(number)-й семестр" }
    var years: String {
        let next = (year + 1) % 100
        return "\(year)/\(next < 10 ? "0" : "")\(next)"
    }
}

/// Учебный год (по году начала) для даты. Со 2 по 31 августа — следующий, ещё не начавшийся.
func academicYear(of d: Date) -> Int {
    let t = dateOnly(d)
    let y = yearOf(t)
    if t >= makeDate(y, 9, 1) { return y }
    if t > makeDate(y, 8, 1) { return y }
    return y - 1
}

/// Дата начала 2-го семестра для учебного года или nil, если 1-й семестр ещё не завершён.
func semesterSplit(_ year: Int, _ splits: [String: String]) -> Date? {
    guard let s = parseYmd(splits["\(year)"] ?? "") else { return nil }
    let first = makeDate(year, 9, 1)
    let last = makeDate(year + 1, 8, 1)
    if s < first || s > last { return nil }
    return s
}

func semesterFor(_ now: Date, _ splits: [String: String]) -> Semester {
    let t = dateOnly(now)
    let y = academicYear(of: t)
    let yStart = makeDate(y, 9, 1)
    let yEnd = makeDate(y + 1, 8, 1)
    let split = semesterSplit(y, splits)
    if t < yStart {
        return Semester(year: y, number: 1, start: yStart, end: yEnd, upcoming: true)
    }
    if let split = split, t >= split {
        return Semester(year: y, number: 2, start: split, end: yEnd)
    }
    return Semester(year: y, number: 1, start: yStart, end: split.map { addDays($0, -1) } ?? yEnd)
}

/// Завершить 1-й семестр можно, пока идёт именно он (не каникулы и не 2-й семестр).
func canEndSemester(_ now: Date, _ splits: [String: String]) -> Bool {
    let s = semesterFor(now, splits)
    return s.number == 1 && !s.upcoming
}

func semesterUnexcusedHours(_ list: [Absence], _ s: Semester) -> Int {
    unexcusedHoursBetween(list, s.start, s.end)
}

/// Ключи для запоминания скрытых предупреждений.
func monthDismissKey(_ now: Date) -> String { "m:\(monthKey(now))" }
func semesterDismissKey(_ s: Semester) -> String { "s:\(s.key)" }
