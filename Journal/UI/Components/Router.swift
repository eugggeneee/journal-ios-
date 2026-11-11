import SwiftUI

/// Все шторки приложения. Каждая открывается поверх вкладок через единый [Router].
enum ActiveSheet: Identifiable {
    case grade(edit: Grade?, subject: String?, date: Date?)
    case absenceQuick(date: Date, lesson: Int?)
    case absenceLesson(date: Date, slot: LessonSlot)
    case absenceWholeDay(date: Date, slots: [LessonSlot])
    case absenceForm(edit: Absence?, date: Date?)
    case lesson(date: Date, slot: LessonSlot)
    case mark(date: Date, lesson: Int?, edit: DayMark?)
    case bells(date: Date)
    case group
    case datePicker(selected: Date, onPick: (Date) -> Void)
    case semester(Semester, hours: Int)

    var id: String {
        switch self {
        case .grade(let edit, _, _): return "grade-\(edit?.id ?? "new")"
        case .absenceQuick: return "absence-quick"
        case .absenceLesson(let d, let s): return "absence-lesson-\(ymd(d))-\(s.number)"
        case .absenceWholeDay(let d, _): return "absence-day-\(ymd(d))"
        case .absenceForm(let edit, _): return "absence-form-\(edit?.id ?? "new")"
        case .lesson(let d, let s): return "lesson-\(ymd(d))-\(s.number)"
        case .mark(let d, let l, let e): return "mark-\(ymd(d))-\(l ?? -1)-\(e?.id ?? "new")"
        case .bells(let d): return "bells-\(ymd(d))"
        case .group: return "group"
        case .datePicker: return "date-picker"
        case .semester(let s, _): return "semester-\(s.key)"
        }
    }
}

@MainActor
@Observable
final class Router {
    var sheet: ActiveSheet?

    func present(_ s: ActiveSheet) { sheet = s }
    func dismiss() { sheet = nil }
}
