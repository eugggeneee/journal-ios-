import Foundation
import Observation

/// Всё состояние приложения и сохранение на устройстве.
@MainActor
@Observable
final class AppStore {
    static let maxCached = 400
    private static let backupId = "journal"

    var settings = Settings()
    var grades: [Grade] = []
    var absences: [Absence] = []
    var marks: [DayMark] = []
    /// Кэш расписания: «группа|yyyy-MM-dd».
    private var cache: [String: DaySchedule] = [:]

    @ObservationIgnored private let directory: URL
    private var dataURL: URL { directory.appendingPathComponent("data_v1.json") }
    private var cacheURL: URL { directory.appendingPathComponent("sched_v1.json") }

    var hasGroup: Bool { !settings.group.isEmpty }
    var onboarded: Bool { settings.onboarded }

    /// Папка по умолчанию — Application Support/Journal.
    init(directory: URL? = nil) {
        let dir: URL
        if let directory = directory {
            dir = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            dir = base.appendingPathComponent("Journal", isDirectory: true)
        }
        self.directory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        readData()
        readCache()
    }

    // MARK: - Чтение

    private func readData() {
        guard let raw = try? Data(contentsOf: dataURL) else { return }
        // Повреждённые данные не должны ронять приложение.
        guard let decoded = try? JSONSerialization.jsonObject(with: raw) else { return }
        _ = applyBackup(decoded)
    }

    @discardableResult
    private func applyBackup(_ decoded: Any) -> Bool {
        guard let j = decoded as? [String: Any] else { return false }
        settings = Settings(json: j["settings"])
        grades = J.list(j["grades"]).compactMap { Grade(json: $0) }
        absences = J.list(j["absences"]).compactMap { Absence(json: $0) }
        marks = J.list(j["marks"]).compactMap { DayMark(json: $0) }
        return true
    }

    private func readCache() {
        guard let raw = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONSerialization.jsonObject(with: raw) as? [Any] else { return }
        for e in decoded {
            if let s = DaySchedule(json: e) { cache["\(s.group)|\(ymd(s.date))"] = s }
        }
    }

    // MARK: - Запись

    func exportMap() -> [String: Any] {
        [
            "app": AppStore.backupId,
            "version": 2,
            "settings": settings.json,
            "grades": grades.map { $0.json },
            "absences": absences.map { $0.json },
            "marks": marks.map { $0.json },
        ]
    }

    private func saveData() {
        guard let data = try? JSONSerialization.data(withJSONObject: exportMap(), options: [.sortedKeys]) else { return }
        try? data.write(to: dataURL, options: .atomic)
    }

    private func saveCache() {
        let list = cache.values.map { $0.json }
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: []) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func changed() { saveData() }

    // MARK: - Кэш расписания

    func cachedSchedule(group: String, date: Date) -> DaySchedule? { cache["\(group)|\(ymd(date))"] }

    /// Расписание выбранной группы на дату (nil — нет или пусто).
    func cachedSchedule(on date: Date) -> DaySchedule? {
        guard let s = cachedSchedule(group: settings.group, date: date), !s.slots.isEmpty else { return nil }
        return s
    }

    func schedules(for group: String) -> [DaySchedule] { cache.values.filter { $0.group == group } }

    func putSchedule(_ s: DaySchedule) {
        cache["\(s.group)|\(ymd(s.date))"] = s
        if cache.count > AppStore.maxCached {
            let sorted = cache.sorted { $0.value.date < $1.value.date }
            for entry in sorted.prefix(cache.count - AppStore.maxCached) { cache.removeValue(forKey: entry.key) }
        }
        saveCache()
    }

    // MARK: - Оценки

    func saveGrade(_ g: Grade) {
        if let i = grades.firstIndex(where: { $0.id == g.id }) { grades[i] = g } else { grades.append(g) }
        changed()
    }

    func deleteGrade(_ id: String) {
        grades.removeAll { $0.id == id }
        changed()
    }

    func grades(of subject: String) -> [Grade] { grades.filter { $0.subject == subject } }

    // MARK: - Пропуски

    /// Один пропуск на пару в день: повторное добавление заменяет предыдущий.
    private func putAbsence(_ a: Absence) {
        if a.lesson > 0 {
            absences.removeAll { $0.id != a.id && $0.lesson == a.lesson && sameDay($0.date, a.date) }
        }
        if let i = absences.firstIndex(where: { $0.id == a.id }) { absences[i] = a } else { absences.append(a) }
    }

    func saveAbsence(_ a: Absence) {
        putAbsence(a)
        changed()
    }

    /// Сохраняет сразу несколько пропусков (одним обновлением интерфейса).
    func saveAbsences(_ list: [Absence]) {
        for a in list { putAbsence(a) }
        changed()
    }

    func deleteAbsence(_ id: String) {
        absences.removeAll { $0.id == id }
        changed()
    }

    /// Удаляет пропуски дня; если [lessons] задан — только эти пары.
    func clearAbsences(on date: Date, lessons: Set<Int>? = nil) {
        absences.removeAll { a in
            sameDay(a.date, date) && (lessons == nil || lessons!.contains(a.lesson))
        }
        changed()
    }

    /// Снимок дня и его восстановление — основа для «Отменить» в любой операции с пропусками.
    func snapshotDay(_ date: Date) -> [Absence] { absences(on: date) }

    func restoreDay(_ date: Date, _ snapshot: [Absence]) {
        absences.removeAll { sameDay($0.date, date) }
        absences.append(contentsOf: snapshot)
        changed()
    }

    func absence(on date: Date, lesson: Int) -> Absence? {
        guard lesson > 0 else { return nil }
        return absences.first { $0.lesson == lesson && sameDay($0.date, date) }
    }

    func absences(on date: Date) -> [Absence] { absences.filter { sameDay($0.date, date) } }

    // MARK: - Пометки

    /// Одна пометка на пару (или на весь день) в день: новая заменяет прежнюю.
    private func putMark(_ m: DayMark) {
        marks.removeAll { $0.id != m.id && $0.lesson == m.lesson && sameDay($0.date, m.date) }
        if let i = marks.firstIndex(where: { $0.id == m.id }) { marks[i] = m } else { marks.append(m) }
    }

    func saveMark(_ m: DayMark) {
        putMark(m)
        changed()
    }

    func deleteMark(_ id: String) {
        marks.removeAll { $0.id == id }
        changed()
    }

    func marks(on date: Date) -> [DayMark] {
        marks.filter { sameDay($0.date, date) }.sorted { $0.lesson < $1.lesson }
    }

    func mark(on date: Date, lesson: Int) -> DayMark? {
        marks.first { $0.lesson == lesson && sameDay($0.date, date) }
    }

    func snapshotMarks(_ date: Date) -> [DayMark] { marks(on: date) }

    func restoreMarks(_ date: Date, _ snapshot: [DayMark]) {
        marks.removeAll { sameDay($0.date, date) }
        marks.append(contentsOf: snapshot)
        changed()
    }

    // MARK: - Звонки

    /// Расписание звонков, действующее в этот день.
    func bellProfile(for date: Date) -> BellProfile { settings.bell(bellKey(for: date)) }

    /// Время конкретной пары в этот день (nil — не задано).
    func bell(on date: Date, lesson: Int) -> BellSlot? { bellProfile(for: date)[lesson] }

    func setBellProfile(_ key: String, _ profile: BellProfile) {
        guard kBellKeys.contains(key) else { return }
        if profile.isEmpty && profile.lunchAfter == 0 {
            settings.bells.removeValue(forKey: key)
        } else {
            settings.bells[key] = profile
        }
        changed()
    }

    // MARK: - Лимиты и семестры

    /// Текущий семестр (на сегодня или на указанную дату).
    func semester(on now: Date = Date()) -> Semester { semesterFor(now, settings.semesterSplits) }

    /// Завершает 1-й семестр: со дня [from] идёт 2-й, до 1 августа.
    @discardableResult
    func endFirstSemester(from: Date) -> Bool {
        let now = dateOnly(from)
        guard canEndSemester(now, settings.semesterSplits) else { return false }
        let sem = semesterFor(now, settings.semesterSplits)
        settings.semesterSplits["\(sem.year)"] = ymd(now)
        changed()
        return true
    }

    /// Возвращает 1-й семестр (отмена завершения) в указанном учебном году.
    func reopenFirstSemester(year: Int) {
        if settings.semesterSplits.removeValue(forKey: "\(year)") != nil { changed() }
    }

    /// Возвращает запись о конце 1-го семестра (для отмены); nil — записи не было.
    func restoreSemesterSplit(year: Int, value: String?) {
        if let value = value {
            settings.semesterSplits["\(year)"] = value
        } else {
            settings.semesterSplits.removeValue(forKey: "\(year)")
        }
        changed()
    }

    func dismissedLevel(_ key: String) -> Int { settings.dismissed[key] ?? 0 }

    /// Скрывает предупреждение периода [key] до уровня [level] включительно.
    /// Записи о прошлых периодах стираются — месяц или семестр сменился, счётчик начинается заново.
    func dismissLimit(_ key: String, level: Int) {
        let kind = String(key.prefix(2))
        settings.dismissed = settings.dismissed.filter { !$0.key.hasPrefix(kind) || $0.key == key }
        if (settings.dismissed[key] ?? 0) >= level {
            changed()
            return
        }
        settings.dismissed[key] = level
        changed()
    }

    func undoDismissLimit(_ key: String, previous: Int) {
        if previous <= 0 {
            settings.dismissed.removeValue(forKey: key)
        } else {
            settings.dismissed[key] = previous
        }
        changed()
    }

    // MARK: - Настройки

    func setGroup(_ group: String) {
        let g = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.isEmpty, g != settings.group else { return }
        settings.group = g
        changed()
    }

    func finishOnboarding() {
        guard !settings.onboarded else { return }
        settings.onboarded = true
        changed()
    }

    func setAbsenceHours(_ v: Int) {
        let h = v == 1 ? 1 : 2
        guard h != settings.absenceHours else { return }
        settings.absenceHours = h
        changed()
    }

    func setAutoRefresh(_ v: Bool) {
        guard v != settings.autoRefresh else { return }
        settings.autoRefresh = v
        changed()
    }

    func addExtraSubject(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !settings.extraSubjects.contains(n) else { return }
        settings.extraSubjects.append(n)
        changed()
    }

    // MARK: - Предметы

    func subjectName(_ key: String) -> String { builtinSubjectNames[key] ?? key }

    /// Все известные предметы: из расписания, оценок, пропусков и добавленные вручную.
    func knownSubjects() -> [String] {
        var set = Set<String>()
        for s in schedules(for: settings.group) {
            for slot in s.slots {
                for e in slot.entries { set.insert(e.subject) }
            }
        }
        for g in grades where !g.subject.isEmpty { set.insert(g.subject) }
        for a in absences where !a.subject.isEmpty { set.insert(a.subject) }
        for s in settings.extraSubjects where !s.isEmpty { set.insert(s) }
        return set.sorted { subjectName($0).localizedCompare(subjectName($1)) == .orderedAscending }
    }

    // MARK: - Очистка

    /// Удаляет оценки, пропуски и пометки; настройки и звонки остаются.
    func clearUserData() {
        grades.removeAll()
        absences.removeAll()
        marks.removeAll()
        changed()
    }

    // MARK: - Резервная копия

    func exportJson() -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: exportMap(), options: options),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// Возвращает текст ошибки или nil, если всё прошло успешно.
    func importJson(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return "Не удалось прочитать данные. Проверьте, что скопирован весь текст."
        }
        guard let map = decoded as? [String: Any], (map["app"] as? String) == AppStore.backupId else {
            return "Это не резервная копия приложения"
        }
        applyBackup(map)
        changed()
        return nil
    }
}
