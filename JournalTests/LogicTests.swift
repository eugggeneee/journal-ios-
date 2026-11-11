import XCTest
@testable import Journal

final class DatesTests: XCTestCase {
    func testPlural() {
        XCTAssertEqual(plural(1, "час", "часа", "часов"), "час")
        XCTAssertEqual(plural(2, "час", "часа", "часов"), "часа")
        XCTAssertEqual(plural(5, "час", "часа", "часов"), "часов")
        XCTAssertEqual(plural(11, "час", "часа", "часов"), "часов")
        XCTAssertEqual(plural(21, "час", "часа", "часов"), "час")
        XCTAssertEqual(plural(112, "час", "часа", "часов"), "часов")
    }

    func testYmdRoundTrip() {
        let d = makeDate(2026, 11, 10)
        XCTAssertEqual(ymd(d), "2026-11-10")
        XCTAssertEqual(parseYmd("2026-11-10"), d)
        XCTAssertNil(parseYmd("2026-13-10"))
        XCTAssertNil(parseYmd("мусор"))
    }

    func testIsoWeekday() {
        XCTAssertEqual(weekday(makeDate(2026, 11, 9)), 1)  // понедельник
        XCTAssertEqual(weekday(makeDate(2026, 11, 10)), 2) // вторник
        XCTAssertEqual(weekday(makeDate(2026, 11, 14)), 6) // суббота
        XCTAssertTrue(isSunday(makeDate(2026, 11, 15)))
    }

    func testDayMath() {
        let a = makeDate(2026, 11, 10)
        XCTAssertEqual(ymd(addDays(a, 25)), "2026-12-05")
        XCTAssertEqual(dayDiff(makeDate(2026, 11, 12), a), 2)
        XCTAssertEqual(dayDiff(a, makeDate(2026, 11, 12)), -2)
        XCTAssertEqual(ymd(monthEnd(makeDate(2028, 2, 10))), "2028-02-29")
    }

    func testFormats() {
        XCTAssertEqual(fmtMin(8 * 60 + 5), "08:05")
        XCTAssertEqual(spanText(100), "1 ч 40 мин")
        XCTAssertEqual(spanText(120), "2 ч")
        XCTAssertEqual(spanText(45), "45 мин")
        XCTAssertEqual(fmtAvg(8.5), "8,50")
    }
}

final class ParserTests: XCTestCase {
    private let html = """
    <html><head><style>p{margin:0}</style></head><body>
    <p>Расписание на 10.11.26</p>
    <p>│ 2412 │ 1 │ Математика │ 101 │ Иванов И.И. │</p>
    <p>│      │ 2 │ АнглЯз │ 202 │ Петрова А.А. │</p>
    <p>│      │ 2 │ АнглЯз │ 203 │ Орлова Б.Б. │</p>
    <p>│ 2413 │ 1 │ РусЯз │ 303 │ Сидоров В.В. │</p>
    <p>│ 2413 │ 2 │ √ │ │ │</p>
    </body></html>
    """

    func testParsesRowsAndHeader() {
        let page = ScheduleParser.parse(html)
        XCTAssertTrue(page.hasText)
        XCTAssertEqual(page.rows.count, 4)
        XCTAssertTrue(page.headerDates.contains("10.11.26"))
    }

    func testSlotsMergeSubgroups() {
        let page = ScheduleParser.parse(html)
        let slots = ScheduleParser.slots(for: page, group: "2412")
        XCTAssertEqual(slots.map { $0.number }, [1, 2])
        XCTAssertEqual(slots[1].entries.count, 2)
        XCTAssertEqual(slots[1].subject, "АнглЯз")
        XCTAssertEqual(ScheduleParser.slots(for: page, group: "2413").count, 1)
        XCTAssertTrue(ScheduleParser.slots(for: page, group: "9999").isEmpty)
    }

    func testEntities() {
        let page = ScheduleParser.parse("<body><p>│ 2412 │ 1 │ Физика&nbsp;и &amp; химия │ 1 │ Т │</p></body>")
        XCTAssertEqual(page.rows.first?.entry.subject, "Физика и & химия")
    }

    func testPageMatchesDate() {
        let page = ScheduleParser.parse(html)
        XCTAssertTrue(ScheduleService.pageMatches(page, makeDate(2026, 11, 10)))
        XCTAssertFalse(ScheduleService.pageMatches(page, makeDate(2027, 11, 10)))
    }

    func testCp1251() {
        XCTAssertEqual(decodeCp1251([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]), "Привет")
    }

    func testUrl() {
        XCTAssertEqual(ScheduleService.url(for: makeDate(2026, 10, 30))?.absoluteString,
                       "https://bseumtc.by/schedule/public/rasp/PODNAM%2030_10.htm")
    }
}

final class BellsTests: XCTestCase {
    func testPresetsAreValid() {
        XCTAssertEqual(kBellPresets.count, 3)
        for p in kBellPresets {
            XCTAssertNil(p.profile.problem, p.title)
        }
    }

    func testGenerate() {
        var plan = BellPlan()
        let plain = generateBells(plan)
        XCTAssertEqual(plain[1]?.start, 510)
        XCTAssertEqual(plain[1]?.end, 600)
        XCTAssertEqual(plain[2]?.start, 610)
        plan.lunchAfter = 2
        let lunch = generateBells(plan)
        XCTAssertEqual(lunch[3]?.start, 730)
        XCTAssertEqual(lunch.lunchAfter, 2)
        XCTAssertNil(lunch.problem)
    }

    func testDayClock() {
        let p = kBellPresets[0].profile
        XCTAssertEqual(dayClock(p, [1, 2, 3], 8 * 60).phase, .before)
        let lesson = dayClock(p, [1, 2, 3], 8 * 60 + 30)
        XCTAssertEqual(lesson.phase, .lesson)
        XCTAssertEqual(lesson.pair, 1)
        XCTAssertEqual(lesson.left, 90)
        XCTAssertEqual(dayClock(p, [1, 2, 3], 9 * 60 + 10).phase, .innerBreak)
        let gap = dayClock(p, [1, 2, 3], 10 * 60 + 5)
        XCTAssertEqual(gap.phase, .gap)
        XCTAssertEqual(gap.next, 2)
        XCTAssertEqual(gap.left, 5)
        XCTAssertEqual(dayClock(p, [1, 2, 3], 22 * 60).phase, .after)
        XCTAssertEqual(dayClock(BellProfile(), [1], 600).phase, .none)
    }

    func testGapLabels() {
        let p = kBellPresets[0].profile
        XCTAssertEqual(gapLabel(p, 1), "Перерыв 10 мин")
        XCTAssertEqual(gapLabel(p, 2), "Обед 30 мин")
        XCTAssertEqual(gapBetween(p, 1, 3)?.hasPrefix("Окно"), true)
    }

    func testBellKey() {
        XCTAssertEqual(bellKey(for: makeDate(2026, 11, 14)), kBellSat)
        XCTAssertEqual(bellKey(for: makeDate(2026, 11, 13)), kBellWeek)
    }

    func testProblemDetection() {
        let bad = BellProfile(slots: [1: BellSlot(start: 600, end: 700), 2: BellSlot(start: 650, end: 740)])
        XCTAssertNotNil(bad.problem)
        XCTAssertFalse(BellSlot(start: 600, end: 600).valid)
    }
}

final class LimitsTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(limitLevel(6, warnFrom: 7, limit: 10), .ok)
        XCTAssertEqual(limitLevel(7, warnFrom: 7, limit: 10), .near)
        XCTAssertEqual(limitLevel(10, warnFrom: 7, limit: 10), .reached)
    }

    func testAcademicYear() {
        XCTAssertEqual(academicYear(of: makeDate(2026, 11, 10)), 2026)
        XCTAssertEqual(academicYear(of: makeDate(2027, 1, 10)), 2026)
        XCTAssertEqual(academicYear(of: makeDate(2026, 8, 1)), 2025)
        XCTAssertEqual(academicYear(of: makeDate(2026, 8, 15)), 2026)
        XCTAssertEqual(academicYear(of: makeDate(2026, 9, 1)), 2026)
    }

    func testSemesters() {
        let none: [String: String] = [:]
        let first = semesterFor(makeDate(2026, 11, 10), none)
        XCTAssertEqual(first.number, 1)
        XCTAssertEqual(ymd(first.start), "2026-09-01")
        XCTAssertTrue(canEndSemester(makeDate(2026, 11, 10), none))

        let split = ["2026": "2027-01-25"]
        let before = semesterFor(makeDate(2027, 1, 10), split)
        XCTAssertEqual(before.number, 1)
        XCTAssertEqual(ymd(before.end), "2027-01-24")
        let second = semesterFor(makeDate(2027, 2, 1), split)
        XCTAssertEqual(second.number, 2)
        XCTAssertEqual(ymd(second.start), "2027-01-25")
        XCTAssertFalse(canEndSemester(makeDate(2027, 2, 1), split))

        let holidays = semesterFor(makeDate(2026, 8, 15), none)
        XCTAssertTrue(holidays.upcoming)
        XCTAssertFalse(canEndSemester(makeDate(2026, 8, 15), none))
    }

    func testHours() {
        let list = [
            Absence(id: "1", date: makeDate(2026, 11, 2), lesson: 1, subject: "A", hours: 2),
            Absence(id: "2", date: makeDate(2026, 11, 3), lesson: 1, subject: "A", hours: 1, excused: true),
            Absence(id: "3", date: makeDate(2026, 10, 30), lesson: 1, subject: "A", hours: 2),
        ]
        XCTAssertEqual(monthUnexcusedHours(list, makeDate(2026, 11, 10)), 2)
        XCTAssertEqual(unexcusedHoursBetween(list, makeDate(2026, 10, 1), makeDate(2026, 11, 30)), 4)
    }
}

final class StatsTests: XCTestCase {
    func testGradeStats() {
        let g = [
            Grade(id: "a", subject: "М", value: 8, date: makeDate(2026, 11, 1)),
            Grade(id: "b", subject: "М", value: 10, date: makeDate(2026, 11, 2)),
            Grade(id: "c", subject: "Ф", value: 6, date: makeDate(2026, 11, 3)),
        ]
        let s = GradeStats.of(g)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.average ?? 0, 8, accuracy: 0.0001)
        XCTAssertEqual(s.distribution[7], 1)
        XCTAssertEqual(s.distribution[9], 1)
        XCTAssertEqual(s.distribution[5], 1)
        let m = s.subjects.first { $0.subject == "М" }
        XCTAssertEqual(m?.average ?? 0, 9, accuracy: 0.0001)
        XCTAssertEqual(m?.lastImpact ?? 0, 1, accuracy: 0.0001)
        XCTAssertNil(GradeStats.of([]).average)
    }

    func testAbsenceStats() {
        let list = [
            Absence(id: "1", date: makeDate(2026, 11, 2), lesson: 1, subject: "А", hours: 2),
            Absence(id: "2", date: makeDate(2026, 11, 3), lesson: 2, subject: "А", hours: 1, excused: true),
        ]
        let s = AbsenceStats.of(list)
        XCTAssertEqual(s.totalHours, 3)
        XCTAssertEqual(s.unexcusedHours, 2)
        XCTAssertEqual(s.bySubjectCount["А"], 2)
    }
}

final class ModelsTests: XCTestCase {
    func testAbsenceJsonRoundTrip() {
        let a = Absence(id: "x", date: makeDate(2026, 11, 10), lesson: 3, subject: "Физика", hours: 1, excused: true, note: "справка")
        let back = Absence(json: a.json)
        XCTAssertEqual(back, a)
    }

    func testGradeRejectsBadValue() {
        XCTAssertNil(Grade(json: ["id": "1", "s": "A", "v": 11, "d": "2026-11-10"]))
        XCTAssertNil(Grade(json: ["id": "1", "s": "A", "v": 0, "d": "2026-11-10"]))
        XCTAssertNotNil(Grade(json: ["id": "1", "s": "A", "v": 10, "d": "2026-11-10"]))
    }

    func testBellSlotJson() {
        XCTAssertNil(BellSlot(json: [100, 50]))
        let s = BellSlot(json: [500, 600, 545, 555])
        XCTAssertEqual(s?.breakMinutes, 10)
        // Перерыв вне пары отбрасывается, сама пара остаётся.
        let t = BellSlot(json: [500, 600, 700, 710])
        XCTAssertNotNil(t)
        XCTAssertFalse(t?.hasBreak ?? true)
    }
}

@MainActor
final class StoreTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPersistence() {
        let dir = tempDir()
        let a = AppStore(directory: dir)
        a.setGroup("2412")
        a.finishOnboarding()
        a.saveGrade(Grade(id: "g1", subject: "Математика", value: 9, date: makeDate(2026, 11, 10)))
        a.saveMark(DayMark(id: "m1", date: makeDate(2026, 11, 10), lesson: 0, label: "ОКР"))

        let b = AppStore(directory: dir)
        XCTAssertEqual(b.settings.group, "2412")
        XCTAssertTrue(b.onboarded)
        XCTAssertEqual(b.grades.count, 1)
        XCTAssertEqual(b.marks.first?.label, "ОКР")
    }

    func testOneAbsencePerLesson() {
        let s = AppStore(directory: tempDir())
        let d = makeDate(2026, 11, 10)
        s.saveAbsence(Absence(id: "a", date: d, lesson: 2, subject: "X", hours: 2))
        s.saveAbsence(Absence(id: "b", date: d, lesson: 2, subject: "X", hours: 1, excused: true))
        XCTAssertEqual(s.absences.count, 1)
        XCTAssertEqual(s.absences.first?.id, "b")
    }

    func testSnapshotRestore() {
        let s = AppStore(directory: tempDir())
        let d = makeDate(2026, 11, 10)
        s.saveAbsence(Absence(id: "a", date: d, lesson: 1, subject: "X", hours: 2))
        let snap = s.snapshotDay(d)
        s.clearAbsences(on: d)
        XCTAssertTrue(s.absences.isEmpty)
        s.restoreDay(d, snap)
        XCTAssertEqual(s.absences.count, 1)
    }

    func testExportImport() {
        let a = AppStore(directory: tempDir())
        a.setGroup("2412")
        a.saveGrade(Grade(id: "g1", subject: "Физика", value: 7, date: makeDate(2026, 11, 10), kind: "Тест"))
        a.saveAbsence(Absence(id: "x", date: makeDate(2026, 11, 10), lesson: 1, subject: "Физика", hours: 2))
        a.setBellProfile(kBellWeek, kBellPresets[0].profile)
        let text = a.exportJson()

        let b = AppStore(directory: tempDir())
        XCTAssertNil(b.importJson(text))
        XCTAssertEqual(b.settings.group, "2412")
        XCTAssertEqual(b.grades.first?.kind, "Тест")
        XCTAssertEqual(b.absences.count, 1)
        XCTAssertEqual(b.settings.bell(kBellWeek), kBellPresets[0].profile)
        XCTAssertNotNil(b.importJson("не json"))
        XCTAssertNotNil(b.importJson("{\"app\":\"other\"}"))
    }

    func testSemesterEndAndDismiss() {
        let s = AppStore(directory: tempDir())
        XCTAssertTrue(s.endFirstSemester(from: makeDate(2026, 11, 10)))
        XCTAssertFalse(s.endFirstSemester(from: makeDate(2026, 11, 20)))
        s.reopenFirstSemester(year: 2026)
        XCTAssertTrue(s.endFirstSemester(from: makeDate(2026, 11, 20)))

        s.dismissLimit("m:2026-11", level: 1)
        XCTAssertEqual(s.dismissedLevel("m:2026-11"), 1)
        s.dismissLimit("m:2026-12", level: 2)
        XCTAssertEqual(s.dismissedLevel("m:2026-11"), 0)
        XCTAssertEqual(s.dismissedLevel("m:2026-12"), 2)
    }
}
