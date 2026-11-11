import Foundation

struct SubjectStat: Identifiable {
    let subject: String
    /// По возрастанию даты.
    let grades: [Grade]

    var id: String { subject }
    var count: Int { grades.count }
    var average: Double {
        guard !grades.isEmpty else { return 0 }
        return Double(grades.reduce(0) { $0 + $1.value }) / Double(grades.count)
    }
    var last: Grade? { grades.last }

    /// Как последняя оценка изменила средний балл (nil, если оценка одна).
    var lastImpact: Double? {
        guard grades.count >= 2 else { return nil }
        let before = grades.dropLast()
        let prev = Double(before.reduce(0) { $0 + $1.value }) / Double(before.count)
        return average - prev
    }
}

struct GradeStats {
    let count: Int
    let average: Double?
    let subjects: [SubjectStat]
    /// Сколько оценок каждого достоинства: индекс 0 — «1», индекс 9 — «10».
    let distribution: [Int]

    static func of(_ grades: [Grade]) -> GradeStats {
        var dist = [Int](repeating: 0, count: 10)
        if grades.isEmpty { return GradeStats(count: 0, average: nil, subjects: [], distribution: dist) }
        let sorted = grades.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.id < b.id
        }
        var order: [String] = []
        var by: [String: [Grade]] = [:]
        var sum = 0
        for g in sorted {
            if by[g.subject] == nil { order.append(g.subject) }
            by[g.subject, default: []].append(g)
            sum += g.value
            dist[min(9, max(0, g.value - 1))] += 1
        }
        let subjects = order.map { SubjectStat(subject: $0, grades: by[$0] ?? []) }
        return GradeStats(count: sorted.count, average: Double(sum) / Double(sorted.count), subjects: subjects, distribution: dist)
    }
}

struct AbsenceStats {
    let totalHours: Int
    let excusedHours: Int
    let bySubjectHours: [String: Int]
    /// Сколько записей о пропусках по каждому предмету.
    let bySubjectCount: [String: Int]
    /// Дата последнего пропуска по каждому предмету.
    let lastBySubject: [String: Date]

    var unexcusedHours: Int { totalHours - excusedHours }

    static func of(_ list: [Absence]) -> AbsenceStats {
        var total = 0
        var excused = 0
        var hours: [String: Int] = [:]
        var count: [String: Int] = [:]
        var last: [String: Date] = [:]
        for a in list {
            total += a.hours
            if a.excused { excused += a.hours }
            hours[a.subject, default: 0] += a.hours
            count[a.subject, default: 0] += 1
            if let prev = last[a.subject] {
                if a.date > prev { last[a.subject] = a.date }
            } else {
                last[a.subject] = a.date
            }
        }
        return AbsenceStats(totalHours: total, excusedHours: excused, bySubjectHours: hours,
                            bySubjectCount: count, lastBySubject: last)
    }
}
