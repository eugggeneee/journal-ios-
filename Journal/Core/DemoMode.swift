import Foundation

/// Демо-режим для автоматических скриншотов в CI. Включается только аргументами запуска
/// `-demo` (тестовые данные) или `-onboarding` (чистый первый запуск) и только в Debug-сборке.
/// В выпускной сборке (IPA) всегда выключен.
enum DemoMode {
    static let demo: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        return false
        #endif
    }()

    static let fresh: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-onboarding")
        #else
        return false
        #endif
    }()

    static var enabled: Bool { demo || fresh }

    /// В демо воскресенье не показываем: стартуем с понедельника.
    static var startOffset: Int { demo && isSunday(today()) ? 1 : 0 }

    /// В демо «сейчас» всегда 10:35 — идёт вторая пара, видна карточка «Сейчас».
    static func clock(_ d: Date) -> Date {
        guard demo else { return d }
        return Cal.cal.date(bySettingHour: 10, minute: 35, second: 0, of: d) ?? d
    }

    @MainActor
    static func makeStore() -> AppStore {
        guard enabled else { return AppStore() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("journal-demo-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(directory: dir)
        if demo { seed(store) }
        return store
    }

    // MARK: - Данные

    private static let template: [(String, String, String)] = [
        ("Математика", "101", "Иванов И.И."),
        ("АнглЯз", "202", "Петрова А.А."),
        ("Физика", "305", "Сидоров В.В."),
        ("ИнформТехнол", "410", "Козлов Д.С."),
    ]

    private static let saturday: [(String, String, String)] = [
        ("РусЯз", "108", "Орлова Е.Н."),
        ("Математика", "101", "Иванов И.И."),
        ("ОхранаТруда", "212", "Лебедев П.Р."),
    ]

    @MainActor
    private static func seed(_ s: AppStore) {
        let group = "2412"
        s.setGroup(group)
        s.finishOnboarding()
        s.setBellProfile(kBellWeek, kBellPresets[0].profile)
        s.setBellProfile(kBellSat, kBellPresets[2].profile)

        let t = today()
        for offset in -20...14 {
            let d = addDays(t, offset)
            if isSunday(d) { continue }
            let rows = isSaturday(d) ? saturday : template
            let slots = rows.enumerated().map { i, r in
                LessonSlot(number: i + 1, entries: [LessonEntry(subject: r.0, room: r.1, teacher: r.2)])
            }
            s.putSchedule(DaySchedule(date: d, group: group, slots: slots, fetchedAt: Date()))
        }

        let grades: [(String, Int, Int, String)] = [
            ("Математика", 9, 2, "Контрольная"), ("Математика", 8, 5, "Ответ"), ("Математика", 10, 9, "Тест"),
            ("Математика", 9, 14, "Практическая"), ("Математика", 8, 20, "Ответ"),
            ("Физика", 7, 3, "Лабораторная"), ("Физика", 8, 10, "Ответ"), ("Физика", 7, 18, "Контрольная"),
            ("АнглЯз", 9, 1, "Ответ"), ("АнглЯз", 8, 6, "Тест"), ("АнглЯз", 9, 12, "Ответ"), ("АнглЯз", 8, 22, "Самостоятельная"),
            ("РусЯз", 10, 4, "Диктант"), ("РусЯз", 9, 11, "Ответ"),
            ("ИнформТехнол", 8, 7, "Практическая"), ("ИнформТехнол", 9, 15, "Тест"), ("ИнформТехнол", 10, 21, "Практическая"),
            ("ОхранаТруда", 6, 8, "Тест"), ("ОхранаТруда", 7, 16, "Ответ"),
        ]
        for (i, g) in grades.enumerated() {
            s.saveGrade(Grade(id: "demo-g\(i)", subject: g.0, value: g.1, date: addDays(t, -g.2), kind: g.3))
        }

        // Пропуски: всегда в текущем месяце, чтобы показать предупреждение о лимите.
        let d0 = dayOf(t)
        func inMonth(_ back: Int) -> Date { makeDate(yearOf(t), monthOf(t), max(1, d0 - back)) }
        let absences: [(Date, Int, String, Int, Bool)] = [
            (inMonth(0), 3, "Физика", 2, false),
            (inMonth(1), 1, "Математика", 2, false),
            (inMonth(2), 2, "АнглЯз", 2, false),
            (inMonth(3), 4, "ИнформТехнол", 2, false),
            (inMonth(4), 5, "Математика", 1, true),
        ]
        for (i, a) in absences.enumerated() {
            s.saveAbsence(Absence(id: "demo-a\(i)", date: a.0, lesson: a.1, subject: a.2, hours: a.3, excused: a.4))
        }

        s.saveMark(DayMark(id: "demo-m1", date: t, lesson: 3, label: "ОКР"))
    }
}
