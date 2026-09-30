import Foundation

struct DMY: Hashable, Comparable {
    var d: Int, m: Int, y: Int

    static func < (a: DMY, b: DMY) -> Bool { (a.y, a.m, a.d) < (b.y, b.m, b.d) }

    var isValid: Bool {
        let thisYear = Calendar.current.component(.year, from: Date())
        guard (1945...thisYear + 1).contains(y), (1...12).contains(m), d >= 1 else { return false }
        var c = DateComponents(); c.year = y; c.month = m
        let cal = Calendar(identifier: .gregorian)
        guard let first = cal.date(from: c), let days = cal.range(of: .day, in: .month, for: first) else { return false }
        return d <= days.count
    }
}

enum DateStyle: String, CaseIterable, Identifiable {
    case words, numeric
    var id: String { rawValue }
    var label: String { self == .words ? "12 marca 2019 r." : "12.03.2019 r." }
}

enum PLDate {
    static let genitive = ["stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca",
                           "sierpnia", "września", "października", "listopada", "grudnia"]
    private static let foldedGenitive = genitive.map { Fold.fold($0) }
    private static let roman = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]
    // Skróty miesięcy: polskie (Gmail, bankowość) i angielskie (nagłówki e-maili).
    private static let short: [String: Int] = [
        "sty": 1, "lut": 2, "mar": 3, "kwi": 4, "maj": 5, "cze": 6, "lip": 7, "sie": 8, "wrz": 9, "paz": 10, "lis": 11, "gru": 12,
        "jan": 1, "feb": 2, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    static func format(_ date: DMY, style: DateStyle) -> String {
        switch style {
        case .words: return "\(date.d) \(genitive[date.m - 1]) \(date.y) r."
        case .numeric: return String(format: "%02d.%02d.%04d r.", date.d, date.m, date.y)
        }
    }

    static func shortNumeric(_ date: DMY) -> String {
        String(format: "%02d.%02d.%04d", date.d, date.m, date.y)
    }

    // MARK: Wyszukiwanie w tekście

    struct Found { let date: DMY; let range: NSRange }

    private static let digit = "[0-9OoIl]"
    private static let numericDMY = Re("(?<![0-9])(\(digit){1,2})\\s?[./-]\\s?(\(digit){1,2})\\s?[./-]\\s?(\(digit){4})(?![0-9])")
    private static let numericYMD = Re("(?<![0-9])([0-9]{4})[./-]([0-9]{1,2})[./-]([0-9]{1,2})(?![0-9])")
    private static let wordsDMY = Re("(?<![0-9])([0-9]{1,2})\\s*(\(foldedGenitive.joined(separator: "|")))\\s*([0-9]{4})")
    private static let romanDMY = Re("(?<![0-9])([0-9]{1,2})[\\s.]+(xii|xi|x|ix|viii|vii|vi|v|iv|iii|ii|i)[\\s.]+([0-9]{4})")
    private static let shortDMY = Re("(?<![0-9])([0-9]{1,2})[\\s.-]*(\(short.keys.joined(separator: "|")))[a-z]*\\.?[\\s.-]*([0-9]{4})")

    private static func num(_ s: String) -> Int? {
        Int(String(s.map { c -> Character in
            switch c { case "O", "o": return "0"; case "I", "l": return "1"; default: return c }
        }))
    }

    /// Wszystkie daty w tekście złożonym (małe litery, bez ogonków).
    static func findAll(in folded: String) -> [Found] {
        var out: [Found] = []
        func add(_ d: DMY?, _ r: NSRange) {
            guard let d, d.isValid, !out.contains(where: { NSIntersectionRange($0.range, r).length > 0 }) else { return }
            out.append(Found(date: d, range: r))
        }
        for m in wordsDMY.all(in: folded) {
            guard let mon = foldedGenitive.firstIndex(of: folded.sub(m.range(at: 2)).lowercased()),
                  let d = num(folded.sub(m.range(at: 1))), let y = num(folded.sub(m.range(at: 3))) else { continue }
            add(DMY(d: d, m: mon + 1, y: y), m.range)
        }
        for m in numericYMD.all(in: folded) {
            if let y = num(folded.sub(m.range(at: 1))), let mo = num(folded.sub(m.range(at: 2))), let d = num(folded.sub(m.range(at: 3))) {
                add(DMY(d: d, m: mo, y: y), m.range)
            }
        }
        for m in numericDMY.all(in: folded) {
            if let d = num(folded.sub(m.range(at: 1))), let mo = num(folded.sub(m.range(at: 2))), let y = num(folded.sub(m.range(at: 3))) {
                add(DMY(d: d, m: mo, y: y), m.range)
            }
        }
        for m in romanDMY.all(in: folded) {
            if let d = num(folded.sub(m.range(at: 1))), let mo = roman.firstIndex(of: folded.sub(m.range(at: 2)).lowercased()),
               let y = num(folded.sub(m.range(at: 3))) {
                add(DMY(d: d, m: mo + 1, y: y), m.range)
            }
        }
        for m in shortDMY.all(in: folded) {
            if let d = num(folded.sub(m.range(at: 1))), let mo = short[folded.sub(m.range(at: 2)).lowercased()],
               let y = num(folded.sub(m.range(at: 3))) {
                add(DMY(d: d, m: mo, y: y), m.range)
            }
        }
        return out.sorted { $0.range.location < $1.range.location }
    }

    /// Data wpisana ręcznie. Przyjmuje „12.3.2019", „2019-03-12", „12 marca 2019 r." itp.
    /// Zwraca nil, gdy tekst nie jest jedną rozpoznawalną datą.
    static func parseUser(_ input: String) -> DMY? {
        let folded = Fold.fold(Fold.sanitize(input.trimmed))
        guard !folded.isEmpty else { return nil }
        let found = findAll(in: folded)
        guard found.count == 1 else { return nil }
        let rest = (folded as NSString).replacingCharacters(in: found[0].range, with: "")
            .replacingOccurrences(of: "z dnia", with: "")
            .replacingOccurrences(of: "dnia", with: "")
            .replacingOccurrences(of: "roku", with: "")
            .replacingOccurrences(of: "r.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.r").union(.whitespaces))
        return rest.isEmpty ? found[0].date : nil
    }
}
