import Foundation

/// Календарь приложения: григорианский, часовой пояс устройства, неделя с понедельника.
enum Cal {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.autoupdatingCurrent
        c.firstWeekday = 2
        return c
    }()
}

private let weekdayNames = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
private let weekdayShortNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
private let monthsGen = ["января", "февраля", "марта", "апреля", "мая", "июня",
                         "июля", "августа", "сентября", "октября", "ноября", "декабря"]
private let monthsNom = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
                         "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]

func two(_ n: Int) -> String { n >= 0 && n < 10 ? "0\(n)" : "\(n)" }

/// Дата из года, месяца и дня (локальная полночь).
func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Cal.cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
}

func dateOnly(_ d: Date) -> Date { Cal.cal.startOfDay(for: d) }
func today() -> Date { dateOnly(Date()) }

func addDays(_ d: Date, _ n: Int) -> Date {
    let base = dateOnly(d)
    guard let moved = Cal.cal.date(byAdding: .day, value: n, to: base) else { return base }
    return dateOnly(moved)
}

/// Разница в целых календарных днях: a − b.
func dayDiff(_ a: Date, _ b: Date) -> Int {
    Cal.cal.dateComponents([.day], from: dateOnly(b), to: dateOnly(a)).day ?? 0
}

func sameDay(_ a: Date, _ b: Date) -> Bool { Cal.cal.isDate(a, inSameDayAs: b) }

func yearOf(_ d: Date) -> Int { Cal.cal.component(.year, from: d) }
func monthOf(_ d: Date) -> Int { Cal.cal.component(.month, from: d) }
func dayOf(_ d: Date) -> Int { Cal.cal.component(.day, from: d) }

/// День недели как в ISO: понедельник — 1, воскресенье — 7.
func weekday(_ d: Date) -> Int {
    let w = Cal.cal.component(.weekday, from: d) // 1 — воскресенье
    return (w + 5) % 7 + 1
}

func isSunday(_ d: Date) -> Bool { weekday(d) == 7 }
func isSaturday(_ d: Date) -> Bool { weekday(d) == 6 }

func ymd(_ d: Date) -> String {
    String(format: "%04d-%02d-%02d", yearOf(d), monthOf(d), dayOf(d))
}

func parseYmd(_ s: String) -> Date? {
    let p = s.split(separator: "-", omittingEmptySubsequences: false)
    guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
    guard y >= 1, y <= 9999, m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
    return makeDate(y, m, d)
}

func weekdayName(_ d: Date) -> String { weekdayNames[weekday(d) - 1] }
func weekdayShort(_ d: Date) -> String { weekdayShortNames[weekday(d) - 1] }

func longDate(_ d: Date) -> String { "\(weekdayName(d)), \(dayOf(d)) \(monthsGen[monthOf(d) - 1])" }
func shortDate(_ d: Date) -> String { "\(dayOf(d)) \(monthsGen[monthOf(d) - 1])" }
func fullDate(_ d: Date) -> String { "\(dayOf(d)) \(monthsGen[monthOf(d) - 1]) \(yearOf(d))" }
func monthYear(_ d: Date) -> String { "\(monthsNom[monthOf(d) - 1]) \(yearOf(d))" }
func monthWord(_ d: Date) -> String { monthsNom[monthOf(d) - 1].lowercased() }

func hhmm(_ d: Date) -> String {
    two(Cal.cal.component(.hour, from: d)) + ":" + two(Cal.cal.component(.minute, from: d))
}

/// Минуты от полуночи для указанного момента.
func minuteOfDay(_ d: Date = Date()) -> Int {
    Cal.cal.component(.hour, from: d) * 60 + Cal.cal.component(.minute, from: d)
}

/// Минуты от полуночи → «08:30».
func fmtMin(_ m: Int) -> String { two(m / 60) + ":" + two(m % 60) }

func minText(_ m: Int) -> String { "\(m) мин" }

/// Промежуток времени: «45 мин», «2 ч», «1 ч 40 мин».
func spanText(_ m: Int) -> String {
    if m < 60 { return "\(m) мин" }
    let h = m / 60
    let r = m % 60
    return r == 0 ? "\(h) ч" : "\(h) ч \(r) мин"
}

/// Ключ месяца: «2026-11».
func monthKey(_ d: Date) -> String { String(format: "%04d-%02d", yearOf(d), monthOf(d)) }

/// Последний день месяца.
func monthEnd(_ d: Date) -> Date {
    let count = Cal.cal.range(of: .day, in: .month, for: d)?.count ?? 28
    return makeDate(yearOf(d), monthOf(d), count)
}

/// Склонение: plural(2, "час", "часа", "часов") → «часа».
func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let a = abs(n) % 100
    let b = a % 10
    if a > 10 && a < 20 { return many }
    if b > 1 && b < 5 { return few }
    if b == 1 { return one }
    return many
}

func hoursText(_ h: Int) -> String { "\(h) \(plural(h, "час", "часа", "часов"))" }
func pairsText(_ n: Int) -> String { "\(n) \(plural(n, "пара", "пары", "пар"))" }
func gradesText(_ n: Int) -> String { "\(n) \(plural(n, "оценка", "оценки", "оценок"))" }
func subjectsText(_ n: Int) -> String { "\(n) \(plural(n, "предмет", "предмета", "предметов"))" }
func daysText(_ n: Int) -> String { "\(n) \(plural(n, "день", "дня", "дней"))" }
func absencesText(_ n: Int) -> String { "\(n) \(plural(n, "пропуск", "пропуска", "пропусков"))" }

/// 8.5 → «8,50».
func fmtAvg(_ v: Double) -> String {
    String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
}

/// «Сегодня» / «Завтра» / «Вчера» / день недели.
func relativeDay(_ d: Date) -> String {
    switch dayDiff(d, today()) {
    case 0: return "Сегодня"
    case 1: return "Завтра"
    case -1: return "Вчера"
    default: return weekdayName(d)
    }
}

/// Подпись даты в формах: «Сегодня, 10 ноября» или «Пятница, 6 ноября».
func dayCaption(_ d: Date) -> String {
    switch dayDiff(d, today()) {
    case 0: return "Сегодня, \(shortDate(d))"
    case 1: return "Завтра, \(shortDate(d))"
    case -1: return "Вчера, \(shortDate(d))"
    default: return longDate(d)
    }
}
