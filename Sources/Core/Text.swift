import Foundation

// MARK: - Normalizacja tekstu
//
// Reguły dopasowujemy do wersji „złożonej": małe litery, bez polskich znaków.
// Na macOS 12 OCR nie zna polskiego i gubi ogonki, więc „SĄD" bywa „SAD" —
// po złożeniu oba zapisy wyglądają tak samo. Złożenie zachowuje długość w
// jednostkach UTF-16, dzięki czemu zakres znaleziony w tekście złożonym
// wskazuje ten sam fragment w oryginale.

enum Fold {
    /// Oryginał przygotowany do pracy: NFC, bez znaków spoza BMP.
    static func sanitize(_ s: String) -> String {
        let nfc = s.precomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        for scalar in nfc.unicodeScalars {
            out.append(scalar.value > 0xFFFF ? " " : scalar)
        }
        return String(out)
    }

    private static let special: [Unicode.Scalar: Unicode.Scalar] = [
        "ł": "l", "Ł": "l", "ø": "o", "Ø": "o", "đ": "d", "Đ": "d",
    ]

    /// Wymaga tekstu po `sanitize`.
    static func fold(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if let mapped = special[scalar] { out.append(mapped); continue }
            let folded = String(scalar).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if folded.utf16.count == 1, let f = folded.unicodeScalars.first {
                out.append(f)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    static func hasPolishDiacritics(_ s: String) -> Bool {
        s.rangeOfCharacter(from: CharacterSet(charactersIn: "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")) != nil
    }
}

// MARK: - Wyrażenia regularne

final class Re {
    let re: NSRegularExpression
    init(_ pattern: String) {
        re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    }
    func first(in s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    func all(in s: String) -> [NSTextCheckingResult] {
        re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    func matches(_ s: String) -> Bool { first(in: s) != nil }
}

extension String {
    func sub(_ r: NSRange) -> String {
        guard r.location != NSNotFound else { return "" }
        return (self as NSString).substring(with: r)
    }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var collapsedSpaces: String {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
    var letterCount: Int { unicodeScalars.filter { CharacterSet.letters.contains($0) }.count }
    var upperRatio: Double {
        let letters = unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let upper = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        return Double(upper.count) / Double(letters.count)
    }
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
    var lowercasedFirst: String {
        guard let f = first else { return self }
        // Nie ruszamy skrótowców („KRS", „VAT", „PKO").
        let firstWord = split(separator: " ").first.map(String.init) ?? ""
        if firstWord.count > 1 && firstWord == firstWord.uppercased() { return self }
        return f.lowercased() + dropFirst()
    }
}

// MARK: - Kosmetyka nazw z OCR

enum Polish {
    /// Zamienia NAPIS WERSALIKAMI na „Napis zdaniowy", zostawiając skrótowce.
    static func sentenceCase(_ s: String) -> String {
        let clean = s.collapsedSpaces
        guard clean.upperRatio > 0.6 else { return clean.capitalizedFirst }
        let keepUpper: Set<String> = ["vat", "krs", "nip", "regon", "pko", "bp", "s.a.", "sa", "ii", "iii", "iv", "vi", "vii", "viii", "ix", "xi", "xii", "kw", "ceidg", "zus", "us", "pit", "cit", "rp"]
        let words = clean.lowercased().split(separator: " ").map { w -> String in
            keepUpper.contains(Fold.fold(String(w))) ? w.uppercased() : String(w)
        }
        return words.joined(separator: " ").capitalizedFirst
    }

    /// Najczęstsze słowa z pism prawnych w poprawnej pisowni — do łatania
    /// tekstu odczytanego bez polskich znaków (macOS 12).
    private static let dictionary: [String: String] = {
        let words = [
            "sąd", "sądu", "sądowy", "sądowego", "sądzie", "okręgowy", "okręgowego", "najwyższy", "najwyższego",
            "wydział", "wydziału", "cywilny", "gospodarczy", "rodzinny", "nieletnich", "pracy",
            "sprzedaży", "pożyczki", "dzieła", "dzierżawy", "użyczenia", "przedwstępna", "przedwstępnej",
            "świadczenie", "świadczenia", "usług", "pracę", "zlecenia", "najmu", "zamiany", "darowizny",
            "dostawy", "współpracy", "poręczenia", "przelewu", "cesji", "wierzytelności", "ugody",
            "lokalu", "mieszkalnego", "użytkowego", "nieruchomości", "gruntowej", "własności",
            "spółka", "spółki", "spółdzielnia", "spółdzielni", "mieszkaniowa", "mieszkaniowej", "wspólnota", "wspólnoty",
            "zapłaty", "zapłatę", "należności", "odszkodowania", "zadośćuczynienia", "wynagrodzenia",
            "poznań", "poznaniu", "gdańsk", "gdańsku", "wrocław", "wrocławiu", "kraków", "łódź", "łodzi",
            "białystok", "białymstoku", "częstochowa", "częstochowie", "gniezno", "gnieźnie", "leszno", "lesznie",
            "piła", "pile", "śrem", "śremie", "środa", "środzie", "wągrowiec", "wągrowcu", "września", "wrześni",
            "zielona", "zielonej", "góra", "górze", "szczecin", "toruń", "toruniu", "kalisz", "koninie",
            "żabka", "świętokrzyska", "główna", "ogólne", "ogólnych", "sądów",
            "jeżyce", "wilda", "nowe", "śródmieście", "południe", "północ", "wschód", "zachód", "fabryczna",
            "wiśniewska", "wiśniewski", "zielińska", "zieliński", "wójcik", "kamińska", "kamiński", "dąbrowska", "dąbrowski",
            "lewandowska", "szymańska", "szymański", "woźniak", "kozłowska", "kozłowski", "jankowska", "wojciechowska",
            "kwiatkowska", "piotrowska", "grabowska", "pawłowska", "michalska", "królik", "wróbel", "pietrzak",
            "szkoda", "dotyczy", "odszkodowanie", "ubezpieczenie", "ubezpieczeń", "towarzystwo",
        ]
        var map: [String: String] = [:]
        for w in words { map[Fold.fold(w)] = w }
        return map
    }()

    /// Przywraca polskie znaki w słowach, których pisownię znamy. Działa tylko,
    /// gdy tekst nie ma żadnych ogonków (czyli OCR ich nie znał).
    static func restoreDiacritics(_ s: String) -> String {
        guard !Fold.hasPolishDiacritics(s) else { return s }
        func fix(_ t: String) -> String {
            let core = t.trimmingCharacters(in: .punctuationCharacters)
            guard !core.isEmpty, let proper = dictionary[Fold.fold(core)] else { return t }
            var fixed = proper
            if core.first?.isUppercase == true { fixed = fixed.capitalizedFirst }
            if core.count > 1 && core == core.uppercased() { fixed = fixed.uppercased() }
            return t.replacingOccurrences(of: core, with: fixed)
        }
        // Słowa rozdzielamy też po łączniku („Poznan-Grunwald" → „Poznań-Grunwald").
        return s.split(separator: " ", omittingEmptySubsequences: false).map { token in
            token.split(separator: "-", omittingEmptySubsequences: false).map { fix(String($0)) }.joined(separator: "-")
        }.joined(separator: " ")
    }

    static func tidy(_ s: String) -> String {
        restoreDiacritics(sentenceCase(s))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—.").union(.whitespacesAndNewlines))
    }
}
