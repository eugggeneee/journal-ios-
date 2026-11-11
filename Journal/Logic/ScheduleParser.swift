import Foundation

// MARK: - Кодировка windows-1251

private let cp1251High: [UInt32] = [
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
    0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
    0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
    0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
]

func decodeCp1251(_ bytes: [UInt8]) -> String {
    var scalars = String.UnicodeScalarView()
    for b in bytes {
        let code: UInt32
        if b < 0x80 {
            code = UInt32(b)
        } else if b < 0xC0 {
            code = cp1251High[Int(b) - 0x80]
        } else {
            code = 0x0410 + UInt32(b) - 0xC0
        }
        if let s = Unicode.Scalar(code) { scalars.append(s) }
    }
    return String(scalars)
}

/// Определяет кодировку по <meta charset> и декодирует. Если указания нет — UTF-8, а при ошибке windows-1251.
func decodeHtmlBytes(_ data: Data) -> String {
    let bytes = [UInt8](data)
    let headBytes = Array(bytes.prefix(4096))
    let head = String(data: Data(headBytes), encoding: .isoLatin1) ?? ""
    var charset = ""
    if let re = try? NSRegularExpression(pattern: "charset\\s*=\\s*[\"']?\\s*([\\w-]+)", options: [.caseInsensitive]) {
        let ns = head as NSString
        if let m = re.firstMatch(in: head, options: [], range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
            charset = ns.substring(with: m.range(at: 1)).lowercased()
        }
    }
    if charset == "utf-8" || charset == "utf8" {
        return String(decoding: bytes, as: UTF8.self)
    }
    if charset.isEmpty {
        if let s = String(data: data, encoding: .utf8) { return s }
        return decodeCp1251(bytes)
    }
    return decodeCp1251(bytes)
}

// MARK: - Разбор страницы

struct ParsedRow {
    let group: String
    let lesson: Int
    let entry: LessonEntry
}

struct ParsedPage {
    let rows: [ParsedRow]
    /// Даты из заголовков страницы в формате dd.MM.yy (например, «30.10.26»).
    let headerDates: Set<String>
    let hasText: Bool
}

/// Разбор страницы вида «PODNAM dd_MM.htm» (HTML, сохранённый из Word:
/// каждая строка таблицы — отдельный <p> с псевдографикой «│»).
enum ScheduleParser {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Шаблоны ниже заданы в коде и проверены, ошибка компиляции невозможна.
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let commentsRe = regex("<!--.*?-->", [.dotMatchesLineSeparators])
    private static let styleScriptRe = regex("<(style|script)\\b.*?</\\1>", [.dotMatchesLineSeparators, .caseInsensitive])
    private static let bodyRe = regex("<body", [.caseInsensitive])
    private static let pOpenRe = regex("<p\\b[^>]*>", [.caseInsensitive])
    private static let tagsRe = regex("<[^>]*>")
    private static let spacesRe = regex("\\s+")
    private static let entityRe = regex("&(#x[0-9a-fA-F]+|#\\d+|[a-zA-Z]+);")
    private static let dateRe = regex("(\\d{2})\\.(\\d{2})\\.(\\d{2})")

    private static func full(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    private static func isDigits(_ s: String, _ range: ClosedRange<Int>) -> Bool {
        guard range.contains(s.unicodeScalars.count) else { return false }
        return s.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in entityRe.matches(in: s, options: [], range: full(s)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            last = m.range.location + m.range.length
            let whole = ns.substring(with: m.range)
            let e = ns.substring(with: m.range(at: 1))
            var replacement = whole
            if e.hasPrefix("#x") {
                if let c = UInt32(e.dropFirst(2), radix: 16), let u = Unicode.Scalar(c) { replacement = String(Character(u)) }
            } else if e.hasPrefix("#") {
                if let c = UInt32(e.dropFirst(1)), let u = Unicode.Scalar(c) { replacement = String(Character(u)) }
            } else {
                switch e {
                case "nbsp": replacement = " "
                case "amp": replacement = "&"
                case "lt": replacement = "<"
                case "gt": replacement = ">"
                case "quot": replacement = "\""
                case "apos": replacement = "'"
                default: break
                }
            }
            result += replacement
        }
        result += ns.substring(from: last)
        return result
    }

    private static func removing(_ re: NSRegularExpression, from s: String, with template: String = "") -> String {
        re.stringByReplacingMatches(in: s, options: [], range: full(s), withTemplate: template)
    }

    static func parse(_ html: String) -> ParsedPage {
        var s = removing(styleScriptRe, from: removing(commentsRe, from: html))
        if let b = bodyRe.firstMatch(in: s, options: [], range: full(s)) {
            s = (s as NSString).substring(from: b.range.location)
        }

        // Делим текст на абзацы по открывающим тегам <p ...>.
        var chunks: [String] = []
        let ns = s as NSString
        var last = 0
        for m in pOpenRe.matches(in: s, options: [], range: full(s)) {
            chunks.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        chunks.append(ns.substring(from: last))

        var paragraphs: [String] = []
        for chunk in chunks {
            var t = removing(tagsRe, from: chunk)
            t = decodeEntities(t).replacingOccurrences(of: "\u{00A0}", with: " ")
            t = removing(spacesRe, from: t, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { paragraphs.append(t) }
        }

        var rows: [ParsedRow] = []
        var headerText = ""
        var group = ""
        var lesson: Int?

        for p in paragraphs {
            if !p.contains("│") {
                headerText += p + " "
                continue
            }
            var parts = p.components(separatedBy: "│").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let f = parts.first, f.isEmpty { parts.removeFirst() }
            if let l = parts.last, l.isEmpty { parts.removeLast() }
            if parts.count != 5 { continue }

            let g = parts[0], n = parts[1], subj = parts[2], room = parts[3], teacher = parts[4]
            if !g.isEmpty && !isDigits(g, 3...5) { continue } // шапка таблицы
            if !n.isEmpty && !isDigits(n, 1...2) { continue }

            if !g.isEmpty {
                group = g
                lesson = nil
            }
            if !n.isEmpty { lesson = Int(n) }
            guard !group.isEmpty, let lessonNumber = lesson else { continue }
            if subj.isEmpty || subj == "√" { continue } // «√» — служебная отметка без предмета

            rows.append(ParsedRow(group: group, lesson: lessonNumber,
                                  entry: LessonEntry(subject: subj, room: room, teacher: teacher)))
        }

        var dates = Set<String>()
        let headerNS = headerText as NSString
        for m in dateRe.matches(in: headerText, options: [], range: full(headerText)) {
            dates.insert(headerNS.substring(with: m.range))
        }
        return ParsedPage(rows: rows, headerDates: dates, hasText: !paragraphs.isEmpty)
    }

    /// Собирает пары одной группы: подгруппы с одним номером — в один слот.
    static func slots(for page: ParsedPage, group: String) -> [LessonSlot] {
        var byNumber: [Int: [LessonEntry]] = [:]
        for r in page.rows where r.group == group {
            var list = byNumber[r.lesson] ?? []
            if !list.contains(r.entry) { list.append(r.entry) }
            byNumber[r.lesson] = list
        }
        return byNumber.keys.sorted().map { LessonSlot(number: $0, entries: byNumber[$0] ?? []) }
    }
}
