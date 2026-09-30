import Foundation

enum Numbering: String, CaseIterable, Identifiable {
    case dot, paren, word
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dot: return "1."
        case .paren: return "1)"
        case .word: return "Załącznik nr 1 –"
        }
    }
    func prefix(_ n: Int) -> String {
        switch self {
        case .dot: return "\(n). "
        case .paren: return "\(n)) "
        case .word: return "Załącznik nr \(n) – "
        }
    }
}

enum LineEnding: String, CaseIterable, Identifiable {
    case semicolon, none
    var id: String { rawValue }
    var label: String { self == .semicolon ? "Średniki, kropka na końcu" : "Bez znaków na końcu" }
}

struct ListOptions {
    var numbering: Numbering = .dot
    var dateStyle: DateStyle = .words
    var ending: LineEnding = .semicolon
    var startAt: Int = 1
    var header: Bool = true
    var lowercaseStart: Bool = false
}

/// Pozycja listy w postaci, jaką edytuje użytkownik.
struct ListEntry {
    var title: String
    var dateText: String
    var detail: String
    var fallbackName: String
}

enum ListFormatter {
    /// Opis jednej pozycji bez numeru, np. „Akt notarialny z dnia 12 marca 2019 r., Rep. A nr 1234/2019".
    static func describe(_ e: ListEntry, style: DateStyle, lowercaseStart: Bool = false) -> String {
        var text = e.title.collapsedSpaces
        if text.isEmpty { text = "[uzupełnij opis: \(e.fallbackName)]" }
        let dateRaw = e.dateText.trimmed
        if !dateRaw.isEmpty {
            if let d = PLDate.parseUser(dateRaw) {
                text += " z dnia " + PLDate.format(d, style: style)
            } else {
                text += " " + dateRaw   // wpis własny, np. „z marca 2019 r." albo „(bez daty)"
            }
        }
        let detail = e.detail.collapsedSpaces.trimmingCharacters(in: CharacterSet(charactersIn: ",; "))
        if !detail.isEmpty { text += ", " + detail }
        return lowercaseStart ? text.lowercasedFirst : text
    }

    static func render(_ entries: [ListEntry], options o: ListOptions) -> String {
        var out: [String] = []
        if o.header { out.append("Załączniki:") }
        for (idx, e) in entries.enumerated() {
            var line = o.numbering.prefix(o.startAt + idx) + describe(e, style: o.dateStyle, lowercaseStart: o.lowercaseStart)
            if o.ending == .semicolon {
                line = line.trimmingCharacters(in: CharacterSet(charactersIn: ";, "))
                if idx < entries.count - 1 { line += ";" }
                else if !line.hasSuffix(".") { line += "." }
            }
            out.append(line)
        }
        return out.joined(separator: "\n") + "\n"
    }
}
