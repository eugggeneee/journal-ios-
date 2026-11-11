import Foundation
import Observation

enum FetchStatus {
    case ok, notPublished, noGroup, sunday, offline, error
}

struct FetchResult {
    var status: FetchStatus
    var slots: [LessonSlot]? = nil
    var page: ParsedPage? = nil
    var message: String? = nil
}

/// Сетевой слой: строит адрес, скачивает страницу и разбирает её.
final class ScheduleService: @unchecked Sendable {
    static let base = "https://bseumtc.by/schedule/public/rasp/"

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// https://bseumtc.by/schedule/public/rasp/PODNAM%2030_10.htm
    static func url(for d: Date) -> URL? {
        URL(string: "\(base)PODNAM%20\(two(dayOf(d)))_\(two(monthOf(d))).htm")
    }

    /// Страница должна относиться именно к запрошенной дате (в адресе нет года).
    static func pageMatches(_ page: ParsedPage, _ d: Date) -> Bool {
        if page.headerDates.isEmpty { return true }
        let expected = "\(two(dayOf(d))).\(two(monthOf(d))).\(two(yearOf(d) % 100))"
        return page.headerDates.contains(expected)
    }

    /// Скачивает и разбирает страницу дня целиком (все группы).
    func download(_ date: Date) async -> FetchResult {
        if isSunday(date) { return FetchResult(status: .sunday) }
        guard let url = ScheduleService.url(for: date) else {
            return FetchResult(status: .error, message: "Некорректный адрес")
        }
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
        } catch let e as URLError where e.code == .timedOut {
            return FetchResult(status: .offline, message: "Сайт не отвечает")
        } catch {
            return FetchResult(status: .offline, message: "Нет подключения к интернету")
        }
        guard let http = response as? HTTPURLResponse else {
            return FetchResult(status: .error, message: "Некорректный ответ сайта")
        }
        if http.statusCode == 404 || http.statusCode == 403 { return FetchResult(status: .notPublished) }
        if http.statusCode != 200 { return FetchResult(status: .error, message: "Ошибка сайта (\(http.statusCode))") }
        if data.isEmpty { return FetchResult(status: .notPublished) }

        let page = ScheduleParser.parse(decodeHtmlBytes(data))
        if !page.hasText || page.rows.isEmpty { return FetchResult(status: .notPublished) }
        if !ScheduleService.pageMatches(page, date) { return FetchResult(status: .notPublished) }
        return FetchResult(status: .ok, page: page)
    }

    func fetch(_ date: Date, group: String) async -> FetchResult {
        let r = await download(date)
        guard r.status == .ok, let page = r.page else { return r }
        let slots = ScheduleParser.slots(for: page, group: group)
        if slots.isEmpty { return FetchResult(status: .noGroup) }
        return FetchResult(status: .ok, slots: slots)
    }

    /// Список групп, которые сейчас есть на сайте (берётся ближайший опубликованный день).
    func listGroups() async -> (groups: [String], offline: Bool) {
        let t = today()
        for offset in [0, 1, 2, 3, 4, 5, -1, -2, -3, -4, -5, -6] {
            if Task.isCancelled { return ([], false) }
            let r = await download(addDays(t, offset))
            if r.status == .offline { return ([], true) }
            if r.status == .ok, let page = r.page {
                let set = Set(page.rows.map { $0.group })
                let list = set.sorted { a, b in
                    if let x = Int(a), let y = Int(b) { return x < y }
                    return a < b
                }
                return (list, false)
            }
        }
        return ([], false)
    }
}

enum DayStatus {
    case ok, notPublished, noGroup, sunday, offline, error
}

/// Итог для экрана одного дня.
struct DayState {
    var status: DayStatus
    var schedule: DaySchedule? = nil
    var fromCache: Bool = false
    var note: String? = nil
}

/// Репозиторий: кэш + сеть.
@MainActor
@Observable
final class ScheduleRepo {
    @ObservationIgnored let store: AppStore
    @ObservationIgnored let service: ScheduleService
    @ObservationIgnored private var inflight: [String: Task<DayState, Never>] = [:]

    private static let freshFor: TimeInterval = 20 * 60

    init(store: AppStore, service: ScheduleService = ScheduleService()) {
        self.store = store
        self.service = service
    }

    func load(_ date: Date, force: Bool = false) async -> DayState {
        let group = store.settings.group
        let key = "\(group)|\(ymd(date))|\(force)"
        if let running = inflight[key] { return await running.value }
        let task = Task { [weak self] () -> DayState in
            guard let self = self else { return DayState(status: .error) }
            return await self.loadNow(dateOnly(date), group: group, force: force)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    /// Тихая подгрузка ближайших дней в кэш. [respectSetting] — учитывать переключатель «Автообновление».
    func prefetch(days: Int = 4, force: Bool = false, respectSetting: Bool = true) async {
        guard store.hasGroup else { return }
        if respectSetting && !force && !store.settings.autoRefresh { return }
        let t = today()
        await withTaskGroup(of: Void.self) { group in
            for i in 0...days {
                let d = addDays(t, i)
                if isSunday(d) { continue }
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    _ = await self.load(d, force: force)
                }
            }
        }
    }

    private func loadNow(_ date: Date, group: String, force: Bool) async -> DayState {
        if group.isEmpty { return DayState(status: .noGroup) }
        if isSunday(date) { return DayState(status: .sunday) }

        let cached = store.cachedSchedule(group: group, date: date)
        let isPast = date < today()
        let isFresh = cached.map { isPast || Date().timeIntervalSince($0.fetchedAt) < ScheduleRepo.freshFor } ?? false
        if !force, isFresh, let cached = cached {
            return DayState(status: .ok, schedule: cached, fromCache: true)
        }

        let res = await service.fetch(date, group: group)
        switch res.status {
        case .ok:
            let loaded = DaySchedule(date: date, group: group, slots: res.slots ?? [], fetchedAt: Date())
            store.putSchedule(loaded)
            return DayState(status: .ok, schedule: loaded)
        case .sunday:
            return DayState(status: .sunday)
        case .noGroup, .notPublished, .offline, .error:
            if let cached = cached {
                return DayState(status: .ok, schedule: cached, fromCache: true,
                                note: res.status == .offline ? "Нет сети — показано сохранённое расписание" : nil)
            }
            let status: DayStatus
            switch res.status {
            case .offline: status = .offline
            case .error: status = .error
            case .noGroup: status = .noGroup
            default: status = .notPublished
            }
            return DayState(status: status, note: res.message)
        }
    }
}
