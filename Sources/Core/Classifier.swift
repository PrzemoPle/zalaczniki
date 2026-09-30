import Foundation

/// Propozycja opisu załącznika. Pusta lista `reasons` = pewna propozycja.
struct Suggestion {
    var title: String
    var date: DMY?
    var detail: String
    var reasons: [String]
    var kind: String
}

/// Rozpoznaje rodzaj dokumentu z tekstu pierwszej strony — lokalnie, regułami.
final class Classifier {
    private let page: PageText
    private let orig: [String]
    private let fold: [String]
    private let fullF: String
    private let full: String
    private var reasons: [String] = []

    private init(_ page: PageText) {
        self.page = page
        orig = page.lines.map(\.text)
        fold = orig.map(Fold.fold)
        full = orig.joined(separator: "\n")
        fullF = fold.joined(separator: "\n")
    }

    static func classify(_ page: PageText) -> Suggestion {
        Classifier(page).run()
    }

    // MARK: - Przebieg

    private func run() -> Suggestion {
        guard full.letterCount >= 25 else {
            return Suggestion(title: "", date: nil, detail: "",
                              reasons: ["Na tej stronie prawie nie ma tekstu (zdjęcie, odręczne pismo?) — opisz dokument ręcznie."],
                              kind: "brak-tekstu")
        }
        if !page.fromPDFLayer && page.meanConfidence < 0.45 {
            reasons.append("Słaba jakość skanu — porównaj opis z podglądem.")
        }

        var built = detectEmail() ?? strongPass() ?? anywherePass()
        if built == nil, let weak = weakPass() {
            built = weak
            reasons.append("Rodzaj dokumentu rozpoznany z niepewnością.")
        }
        if built == nil { built = letterOrHeading() }

        var s = built ?? Built(kind: "nieznany", title: "", detail: "")
        if s.title.isEmpty { reasons.append("Nie rozpoznano rodzaju dokumentu — wpisz opis.") }
        reasons.append(contentsOf: s.reasons)

        let (date, uncertain) = pickDate()
        if date == nil {
            reasons.append("Nie znaleziono daty dokumentu.")
        } else if uncertain {
            reasons.append("Na stronie jest kilka dat — sprawdź, czy wybrano właściwą.")
        }
        s.title = s.title.collapsedSpaces
        return Suggestion(title: s.title, date: date, detail: s.detail.collapsedSpaces, reasons: reasons, kind: s.kind)
    }

    struct Built {
        var kind: String
        var title: String
        var detail: String
        var reasons: [String] = []
    }

    private struct Rule {
        let kind: String
        let re: Re
        let anywhere: Bool   // fraza na tyle charakterystyczna, że liczy się w dowolnym miejscu strony
        let build: (Classifier, Int, NSTextCheckingResult) -> Built?
    }

    // MARK: - Linie tytułowe

    /// Indeksy linii, które najpewniej są tytułem: duże, wersalikami, krótkie, u góry, wyśrodkowane.
    private lazy var titleLines: [Int] = {
        let n = orig.count
        guard n > 0 else { return [] }
        let heights = page.lines.compactMap { $0.box?.height }.sorted()
        let median = heights.isEmpty ? 0 : heights[heights.count / 2]
        var scored: [(Int, Double)] = []
        for i in 0..<n {
            let text = orig[i]
            let letters = text.letterCount
            guard letters >= 3 else { continue }
            let box = page.lines[i].box
            let pos = box.map { Double($0.midY) } ?? Double(i) / Double(max(n, 1))
            guard pos < (box == nil ? 0.4 : 0.55) else { continue }
            var s = 0.0
            if let b = box, median > 0 { s += min(Double(b.height / median) - 1, 2) * 3 }
            if text.upperRatio > 0.7 && letters >= 4 { s += 2 }
            s += text.count <= 45 ? 1 : -1
            s += (1 - pos) * 1.5
            if let b = box, abs(b.midX - 0.5) < 0.1, b.width < 0.6 { s += 1 }
            scored.append((i, s))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(8).map(\.0)
    }()

    private func strongPass() -> Built? {
        for i in titleLines {
            for rule in Self.rules {
                if let m = rule.re.first(in: fold[i]), let b = rule.build(self, i, m) { return b }
            }
        }
        return nil
    }

    private func anywherePass() -> Built? {
        for rule in Self.rules where rule.anywhere {
            for i in orig.indices {
                if let m = rule.re.first(in: fold[i]), let b = rule.build(self, i, m) { return b }
            }
        }
        return nil
    }

    private func weakPass() -> Built? {
        let limit = max(1, Int(Double(orig.count) * 0.35))
        for i in 0..<min(limit, orig.count) {
            for rule in Self.rules where !rule.anywhere {
                if let m = rule.re.first(in: fold[i]), let b = rule.build(self, i, m) { return b }
            }
        }
        return nil
    }

    // MARK: - Reguły

    private static let rules: [Rule] = [
        Rule(kind: "wypis-aktu", re: Re("^\\W*wypis\\s+aktu\\s+notarialnego"), anywhere: true) { c, _, _ in c.notarial(title: "Wypis aktu notarialnego") },
        Rule(kind: "akt-notarialny", re: Re("akt\\s*notarialny|repertorium\\s*a\\b"), anywhere: true) { c, _, _ in c.notarial(title: "Akt notarialny") },
        Rule(kind: "faktura", re: Re("^\\W*faktura\\b"), anywhere: true) { c, i, _ in c.invoice(line: i) },
        Rule(kind: "paragon", re: Re("paragon\\s*fiskalny|^\\W*paragon\\b"), anywhere: true) { c, _, _ in c.receipt() },
        Rule(kind: "przelew", re: Re("potwierdzenie\\s+(wykonania\\s+|realizacji\\s+)?(przelewu|transakcji|operacji|zlecenia|platnosci)"), anywhere: true) { c, _, _ in c.transfer() },
        Rule(kind: "wyciag", re: Re("^\\W*(wyciag\\s+(z\\s+rachunku|bankowy|nr)|historia\\s+(rachunku|transakcji|operacji)|zestawienie\\s+(operacji|transakcji))"), anywhere: true) { _, _, _ in
            Built(kind: "wyciag", title: "Wyciąg z rachunku bankowego", detail: "")
        },
        Rule(kind: "nakaz", re: Re("^\\W*nakaz\\s+zaplaty"), anywhere: true) { c, _, _ in c.court(kind: "Nakaz zapłaty") },
        Rule(kind: "wyrok", re: Re("^\\W*wyrok\\b"), anywhere: false) { c, _, _ in c.court(kind: "Wyrok") },
        Rule(kind: "postanowienie", re: Re("^\\W*postanowienie\\b"), anywhere: false) { c, _, _ in c.court(kind: "Postanowienie") },
        Rule(kind: "zarzadzenie", re: Re("^\\W*zarzadzenie\\b"), anywhere: false) { c, _, _ in c.court(kind: "Zarządzenie") },
        Rule(kind: "uzasadnienie", re: Re("^\\W*uzasadnienie\\b"), anywhere: false) { c, _, _ in c.court(kind: "Uzasadnienie") },
        Rule(kind: "protokol-rozprawy", re: Re("^\\W*protokol\\s+(z\\s+)?(rozprawy|posiedzenia)"), anywhere: false) { c, _, _ in c.court(kind: "Protokół rozprawy") },
        Rule(kind: "wezwanie", re: Re("wezwanie\\s+do\\s+(zaplaty|zaplacenia|uregulowania)"), anywhere: true) { c, i, _ in c.demand(line: i) },
        Rule(kind: "krs", re: Re("informacja\\s+odpowiadajaca\\s+odpisowi|odpis\\s+(aktualny|pelny)\\s+z\\s+rejestru|krajowy\\s+rejestr\\s+sadowy"), anywhere: true) { c, _, _ in c.krs() },
        Rule(kind: "kw", re: Re("odpis\\s+(zwykly\\s+|zupelny\\s+)?ksiegi\\s+wieczystej|wydruk\\s+(z\\s+)?ksiegi\\s+wieczystej|tresc\\s+ksiegi\\s+wieczystej"), anywhere: true) { c, _, _ in c.landRegister() },
        Rule(kind: "usc", re: Re("odpis\\s+(skrocony|zupelny|wielojezyczny)\\s+aktu\\s+(urodzenia|malzenstwa|zgonu)"), anywhere: true) { c, i, m in
            let rodzaj = ["skrocony": "skrócony", "zupelny": "zupełny", "wielojezyczny": "wielojęzyczny"][c.fold[i].sub(m.range(at: 1))] ?? ""
            let akt = ["urodzenia": "urodzenia", "malzenstwa": "małżeństwa", "zgonu": "zgonu"][c.fold[i].sub(m.range(at: 2))] ?? ""
            return Built(kind: "usc", title: "Odpis \(rodzaj) aktu \(akt)", detail: "")
        },
        Rule(kind: "ceidg", re: Re("centralnej\\s+ewidencji\\s+i\\s+informacji|\\bceidg\\b"), anywhere: false) { _, _, _ in
            Built(kind: "ceidg", title: "Wydruk z Centralnej Ewidencji i Informacji o Działalności Gospodarczej", detail: "")
        },
        Rule(kind: "aneks", re: Re("^\\W*(aneks)\\b"), anywhere: false) { c, i, m in c.heading(i, m, canonical: "Aneks", kind: "aneks") },
        Rule(kind: "umowa", re: Re("^\\W*umowa\\b"), anywhere: false) { c, i, m in c.contract(line: i, match: m) },
    ] + simpleRules

    /// Nagłówki, dla których wystarczy poprawna nazwa plus reszta linii („Oświadczenie o potrąceniu").
    private static let simpleRules: [Rule] = [
        ("odpowiedz\\s+na\\s+reklamacje", "Odpowiedź na reklamację"),
        ("reklamacja", "Reklamacja"),
        ("odpowiedz\\s+na\\s+pozew", "Odpowiedź na pozew"),
        ("pelnomocnictwo", "Pełnomocnictwo"),
        ("zaswiadczenie\\s+lekarskie", "Zaświadczenie lekarskie"),
        ("zaswiadczenie", "Zaświadczenie"),
        ("oswiadczenie", "Oświadczenie"),
        ("karta\\s+informacyjna(\\s+leczenia\\s+szpitalnego)?", "Karta informacyjna leczenia szpitalnego"),
        ("historia\\s+choroby", "Historia choroby"),
        ("wyniki?\\s+badan", "Wyniki badań"),
        ("skierowanie", "Skierowanie"),
        ("opinia", "Opinia"),
        ("ekspertyza", "Ekspertyza"),
        ("kosztorys", "Kosztorys"),
        ("wycena", "Wycena"),
        ("oferta", "Oferta"),
        ("zamowienie", "Zamówienie"),
        ("protokol\\s+zdawczo[\\s-]*odbiorczy", "Protokół zdawczo-odbiorczy"),
        ("protokol\\s+(z\\s+)?odbioru", "Protokół odbioru"),
        ("protokol", "Protokół"),
        ("decyzja", "Decyzja"),
        ("polisa", "Polisa ubezpieczeniowa"),
        ("swiadectwo\\s+pracy", "Świadectwo pracy"),
        ("regulamin", "Regulamin"),
        ("ogolne\\s+warunki", "Ogólne warunki"),
        ("pozew", "Pozew"),
        ("sprzeciw\\s+od\\s+nakazu(\\s+zaplaty)?", "Sprzeciw od nakazu zapłaty"),
        ("zazalenie", "Zażalenie"),
        ("apelacja", "Apelacja"),
        ("wniosek", "Wniosek"),
        ("zawiadomienie", "Zawiadomienie"),
        ("wypowiedzenie", "Wypowiedzenie"),
        ("upomnienie", "Upomnienie"),
        ("zwrotne\\s+potwierdzenie\\s+odbioru", "Zwrotne potwierdzenie odbioru"),
        ("potwierdzenie\\s+nadania", "Potwierdzenie nadania przesyłki"),
        ("karta\\s+gwarancyjna", "Karta gwarancyjna"),
        ("nota\\s+(?:ksiegowa|obciazeniowa|uznaniowa|korygujaca|odsetkowa)", "Nota"),
        ("rachunek", "Rachunek"),
        ("porozumienie", "Porozumienie"),
        ("ugoda", "Ugoda"),
        ("notatka", "Notatka"),
        ("raport", "Raport"),
        ("dokumentacja\\s+fotograficzna", "Dokumentacja fotograficzna"),
    ].map { pattern, canonical in
        Rule(kind: canonical, re: Re("^\\W*(\(pattern))\\b"), anywhere: false) { c, i, m in
            c.heading(i, m, canonical: canonical, kind: canonical)
        }
    }

    // MARK: - Budowniczowie opisów

    /// Nazwa z nagłówka: poprawna forma słowa-klucza + reszta linii do pierwszego „stopera".
    private func heading(_ i: Int, _ m: NSTextCheckingResult, canonical: String, kind: String) -> Built? {
        let line = orig[i]
        let key = m.range(at: 1)
        if kind == "Nota" {
            let raw = fold[i].sub(key)
            let fixes = ["ksiegowa": "księgowa", "obciazeniowa": "obciążeniowa", "korygujaca": "korygująca"]
            let second = raw.split(separator: " ").last.map(String.init) ?? ""
            return Built(kind: kind, title: "Nota " + (fixes[second] ?? second), detail: "")
        }
        let rest = rest(of: line, from: key.location + key.length)
        return Built(kind: kind, title: rest.isEmpty ? canonical : canonical + " " + rest, detail: "")
    }

    private static let stopper = Re("(\\s+z\\s+dnia|\\s+zawart|\\s+sporzadzon|\\s+nr\\b|\\s+numer\\b|,|\\s+\\d{1,2}[./-]\\d{1,2}[./-]\\d{2,4}|\\s+\\(|\\s+w\\s+dniu)")

    /// Reszta linii po słowie-kluczu, przycięta i doprowadzona do porządku.
    private func rest(of line: String, from location: Int) -> String {
        let ns = line as NSString
        guard location < ns.length else { return "" }
        var tail = ns.substring(from: location)
        if let s = Self.stopper.first(in: Fold.fold(tail)) { tail = (tail as NSString).substring(to: s.range.location) }
        tail = tail.trimmingCharacters(in: CharacterSet(charactersIn: " :;-–—.").union(.whitespaces))
        guard tail.letterCount >= 2, tail.count <= 70 else { return "" }
        let lowered = tail.upperRatio > 0.6 ? tail.lowercased() : tail
        return Polish.restoreDiacritics(lowered)
    }

    private func notarial(title: String) -> Built {
        var detail = ""
        if let m = Re("repertorium\\s*a\\s*(?:numer|nr|n\\s?r)?\\.?\\s*:?\\s*([0-9]{1,6})\\s*/\\s*([0-9]{4})").first(in: fullF) {
            detail = "Rep. A nr \(fullF.sub(m.range(at: 1)))/\(fullF.sub(m.range(at: 2)))"
        }
        var t = title
        // Czego dotyczy akt — np. „UMOWA SPRZEDAŻY" pod nagłówkiem.
        let actName = Re("^\\W*(umowa\\s+[a-z ]{3,40}|oswiadczenie\\s+o\\s+[a-z ]{3,40}|testament|darowizna|pelnomocnictwo)")
        for i in orig.indices.prefix(40) {
            if let m = actName.first(in: fold[i]) {
                var name = orig[i].sub(m.range(at: 1))
                if let s = Self.stopper.first(in: Fold.fold(name)) { name = (name as NSString).substring(to: s.range.location) }
                name = Polish.restoreDiacritics(name.trimmed.lowercased())
                if name.letterCount >= 5 { t += " – " + name }
                break
            }
        }
        return Built(kind: "akt-notarialny", title: t, detail: detail,
                     reasons: detail.isEmpty ? ["Nie odczytano numeru repertorium."] : [])
    }

    private func invoice(line i: Int) -> Built {
        let headF = fold[i]
        var label = "Faktura"
        if Re("korygujac|korekta").matches(headF) { label = "Faktura korygująca" }
        else if Re("pro\\s*-?\\s*forma").matches(headF) { label = "Faktura pro forma" }
        else if Re("\\bvat\\b").matches(headF) { label = Re("marza").matches(headF) ? "Faktura VAT marża" : "Faktura VAT" }

        var number = ""
        let numRe = Re("(?:\\bnr|numer|\\bno)\\.?\\s*:?\\s*([a-z0-9][a-z0-9/_.\\-]*[a-z0-9])")
        if let m = numRe.first(in: headF) {
            number = orig[i].sub(m.range(at: 1))
        } else if i + 1 < orig.count, let m = numRe.first(in: fold[i + 1]) {
            number = orig[i + 1].sub(m.range(at: 1))
        } else if let m = Re("(?:numer|nr)\\s+faktury\\s*:?\\s*([a-z0-9][a-z0-9/_.\\-]*[a-z0-9])").first(in: fullF) {
            number = full.sub(m.range(at: 1))
        }
        let title = number.isEmpty ? label : "\(label) nr \(number)"

        let seller = party(Re("^\\W*(sprzedawca|wystawca|sprzedajacy|dostawca|uslugodawca)\\b"))
        var r: [String] = []
        if number.isEmpty { r.append("Nie odczytano numeru faktury.") }
        if seller == nil { r.append("Nie odczytano sprzedawcy.") }
        return Built(kind: "faktura", title: title, detail: seller.map { "wystawiona przez \($0)" } ?? "", reasons: r)
    }

    private func receipt() -> Built {
        let store = knownChain() ?? storeFromHeader()
        var detail = ""
        if let amount = amount(Re("\\bsuma\\s*(?:pln)?\\s*:?\\s*([0-9]{1,3}(?:[ .]?[0-9]{3})*[,.][0-9]{2})")) {
            detail = "na kwotę \(amount)"
        }
        return Built(kind: "paragon", title: store.map { "Paragon fiskalny ze sklepu \($0)" } ?? "Paragon fiskalny",
                     detail: detail, reasons: store == nil ? ["Nie odczytano nazwy sklepu."] : [])
    }

    private func transfer() -> Built {
        var parts: [String] = []
        if let a = amount(Re("kwota(?:\\s+przelewu|\\s+operacji|\\s+transakcji)?\\s*:?\\s*-?([0-9]{1,3}(?:[ .]?[0-9]{3})*[,.][0-9]{2})")) {
            parts.append("na kwotę \(a)")
        }
        // Nazwiska nie odmienimy automatycznie, więc „odbiorca: X" zamiast „na rzecz X".
        if let who = party(Re("^\\W*(nazwa\\s+odbiorcy|odbiorca|beneficjent)\\b")) { parts.append("odbiorca: \(who)") }
        return Built(kind: "przelew", title: "Potwierdzenie przelewu", detail: parts.joined(separator: ", "))
    }

    private func demand(line i: Int) -> Built {
        let f = fold[i]
        var words: [String] = []
        if Re("ostateczne").matches(f) { words.append("ostateczne") }
        if Re("przedsadowe").matches(f) { words.append("przedsądowe") }
        words.append("wezwanie do zapłaty")
        let title = words.joined(separator: " ").capitalizedFirst
        var detail = ""
        if let a = amount(Re("kwot[ya]\\s*:?\\s*([0-9]{1,3}(?:[ .]?[0-9]{3})*[,.][0-9]{2})")) { detail = "na kwotę \(a)" }
        return Built(kind: "wezwanie", title: title, detail: detail)
    }

    private func court(kind: String) -> Built {
        var title = kind
        var r: [String] = []
        if let name = courtName() { title += " " + name } else { r.append("Nie odczytano nazwy sądu.") }
        var detail: [String] = []
        if kind == "Nakaz zapłaty" {
            if fullF.contains("upominawcz") { detail.append("wydany w postępowaniu upominawczym") }
            else if fullF.contains("nakazow") { detail.append("wydany w postępowaniu nakazowym") }
        }
        if let m = Re("sygn(?:\\.|atura)?\\s*(?:akt)?\\s*[:.]?\\s*([ivxl]{1,6}\\s+[a-z]{1,4}(?:\\s+[a-z]{1,3})?\\s*[0-9]{1,6}\\s*/\\s*[0-9]{2,4})").first(in: fullF) {
            detail.append("sygn. akt " + signature(full.sub(m.range(at: 1))))
        }
        return Built(kind: kind, title: title, detail: detail.joined(separator: ", "), reasons: r)
    }

    private func krs() -> Built {
        var detail = ""
        if let m = Re("(?:numer\\s+krs|krs\\s*(?:nr|numer)?)\\s*:?\\s*([0-9]{10})").first(in: fullF) {
            detail = "KRS \(fullF.sub(m.range(at: 1)))"
        }
        return Built(kind: "krs", title: "Informacja odpowiadająca odpisowi aktualnemu z Krajowego Rejestru Sądowego", detail: detail)
    }

    private func landRegister() -> Built {
        var detail = ""
        if let m = Re("([a-z]{2}[0-9][a-z])\\s*/\\s*([0-9]{8})\\s*/\\s*([0-9])").first(in: fullF) {
            detail = "KW nr " + fullF.sub(m.range).replacingOccurrences(of: " ", with: "").uppercased()
        }
        return Built(kind: "kw", title: "Odpis księgi wieczystej", detail: detail,
                     reasons: detail.isEmpty ? ["Nie odczytano numeru księgi wieczystej."] : [])
    }

    private func contract(line i: Int, match m: NSTextCheckingResult) -> Built? {
        var rest = rest(of: orig[i], from: m.range.location + m.range.length)
        // „UMOWA" w osobnej linii, a rodzaj pod spodem („NAJMU LOKALU").
        if rest.isEmpty, i + 1 < orig.count {
            let next = orig[i + 1]
            if next.count <= 50, next.rangeOfCharacter(from: .decimalDigits) == nil,
               !Re("^\\W*(zawarta|zawarty|w\\s+dniu|dnia|pomiedzy)").matches(fold[i + 1]) {
                rest = self.rest(of: next, from: 0)
            }
        }
        return Built(kind: "umowa", title: rest.isEmpty ? "Umowa" : "Umowa " + rest, detail: "",
                     reasons: rest.isEmpty ? ["Nie odczytano rodzaju umowy."] : [])
    }

    // MARK: - E-mail, pismo, nagłówek

    private func detectEmail() -> Built? {
        let top = Array(fold.prefix(max(8, fold.count / 3)))
        let from = top.contains { Re("^\\W*(od|from|nadawca)\\s*:").matches($0) }
        let subjectIdx = fold.firstIndex { Re("^\\W*(temat|subject|tytul)\\s*:").matches($0) }
        guard from, let si = subjectIdx else { return nil }
        let subject = orig[si].replacingOccurrences(of: "^\\W*\\S+\\s*:\\s*", with: "", options: .regularExpression).trimmed
        return Built(kind: "email", title: "Wiadomość e-mail",
                     detail: subject.letterCount >= 2 ? "temat: „\(Polish.restoreDiacritics(subject))”" : "")
    }

    private func letterOrHeading() -> Built? {
        if Re("szanown|^\\W*(dotyczy|dot\\.)\\s*:|w\\s+odpowiedzi\\s+na").matches(fullF) {
            var detail = ""
            if let i = fold.firstIndex(where: { Re("^\\W*(dotyczy|dot\\.)\\s*:").matches($0) }) {
                let subject = orig[i].replacingOccurrences(of: "^\\W*\\S+\\s*:\\s*", with: "", options: .regularExpression).trimmed
                if subject.letterCount >= 3 { detail = "dot. " + Polish.restoreDiacritics(String(subject.prefix(80))) }
            }
            if let sender = letterhead() {
                return Built(kind: "pismo", title: "Pismo \(sender)", detail: detail,
                             reasons: ["Sprawdź nadawcę pisma — odczytano go z nagłówka."])
            }
            return Built(kind: "pismo", title: "Pismo", detail: detail, reasons: ["Dopisz nadawcę pisma (np. „Pismo PZU SA”)."])
        }
        if let i = titleLines.first, orig[i].letterCount >= 4, orig[i].count <= 70 {
            return Built(kind: "naglowek", title: Polish.tidy(orig[i]), detail: "",
                         reasons: ["Nie rozpoznano rodzaju dokumentu — opis wzięto z nagłówka."])
        }
        return nil
    }

    /// Nadawca pisma: pierwsza linia papieru firmowego, o ile nie jest adresem, datą ani adresatem.
    private func letterhead() -> String? {
        let skip = Re("^\\W*(ul\\.|al\\.|os\\.|pl\\.|tel|www|e-?mail|pan\\b|pani\\b|szanown|dotyczy|dot\\.)|\\d{2}-\\d{3}|,\\s*(dnia\\s*)?\\d")
        guard let i = orig.indices.prefix(3).first(where: { orig[$0].letterCount >= 2 }),
              orig[i].count <= 40, !skip.matches(fold[i]), PLDate.findAll(in: fold[i]).isEmpty else { return nil }
        return properCase(orig[i].collapsedSpaces)
    }

    // MARK: - Strony, sklepy, sądy, kwoty

    /// Nazwa strony (sprzedawcy, odbiorcy) — z tej samej linii po dwukropku albo z linii pod spodem.
    private func party(_ label: Re) -> String? {
        guard let i = fold.firstIndex(where: { label.matches($0) }), let m = label.first(in: fold[i]) else { return nil }
        let end = m.range.location + m.range.length
        let after = orig[i].sub(NSRange(location: end, length: (orig[i] as NSString).length - end))
            .trimmingCharacters(in: CharacterSet(charactersIn: " :;-").union(.whitespaces))
        var candidate: String? = after.letterCount >= 3 && !Fold.fold(after).contains("nabywca") ? after : nil
        if candidate == nil, let j = lineBelow(i) { candidate = orig[j] }
        guard var name = candidate else { return nil }
        if let cut = Re("\\s*(\\bnip\\b|\\bul\\.|\\bregon\\b|\\bnabywca\\b|\\d{2}-\\d{3}).*$").first(in: Fold.fold(name)) {
            name = (name as NSString).substring(to: cut.range.location)
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-").union(.whitespaces))
        guard name.letterCount >= 3, !Re("^\\W*(nabywca|odbiorca|kupujacy|platnik)\\b").matches(Fold.fold(name)) else { return nil }
        return Polish.restoreDiacritics(name.collapsedSpaces)
    }

    /// Najbliższa linia pod spodem w tej samej kolumnie (przy układzie „Sprzedawca | Nabywca").
    private func lineBelow(_ i: Int) -> Int? {
        guard let ref = page.lines[i].box else { return i + 1 < orig.count ? i + 1 : nil }
        var best: (Int, CGFloat)?
        for (j, l) in page.lines.enumerated() where j != i {
            guard let b = l.box, b.minY >= ref.maxY - ref.height * 0.3, abs(b.minX - ref.minX) < 0.12 else { continue }
            let dist = b.minY - ref.maxY
            if dist < 0.08, best == nil || dist < best!.1 { best = (j, dist) }
        }
        return best?.0
    }

    private static let chains: [(String, String)] = [
        ("jeronimo martins|biedronka", "Biedronka"), ("\\blidl\\b", "Lidl"), ("\\bzabka\\b", "Żabka"),
        ("kaufland", "Kaufland"), ("carrefour", "Carrefour"), ("auchan", "Auchan"), ("rossmann", "Rossmann"),
        ("\\bhebe\\b", "Hebe"), ("leroy\\s*merlin", "Leroy Merlin"), ("castorama", "Castorama"), ("\\bobi\\b", "OBI"),
        ("media\\s*markt", "MediaMarkt"), ("media\\s*expert|terg\\s+s\\.?a", "Media Expert"), ("euro\\s*net|rtv\\s*euro\\s*agd", "RTV Euro AGD"),
        ("empik", "Empik"), ("\\borlen\\b", "Orlen"), ("pepco", "Pepco"), ("\\baction\\b", "Action"), ("\\bjysk\\b", "JYSK"),
        ("\\bikea\\b", "IKEA"), ("decathlon", "Decathlon"), ("\\bnetto\\b", "Netto"), ("\\bdino\\b", "Dino"),
        ("stokrotka", "Stokrotka"), ("intermarche", "Intermarché"), ("polomarket", "POLOmarket"), ("lewiatan", "Lewiatan"),
        ("\\bshell\\b", "Shell"), ("circle\\s*k", "Circle K"), ("\\bsmyk\\b", "Smyk"), ("\\bccc\\b", "CCC"),
    ]

    private func knownChain() -> String? {
        let head = fold.prefix(10).joined(separator: "\n")
        for (pattern, name) in Self.chains where Re(pattern).matches(head) { return name }
        return nil
    }

    private func storeFromHeader() -> String? {
        let limit = fold.firstIndex { Re("\\bnip\\b").matches($0) } ?? min(6, fold.count)
        let skip = Re("^\\W*(ul\\.|al\\.|os\\.|pl\\.|tel|www|paragon|nip|sklep\\s+nr|kasa)|\\d{2}-\\d{3}")
        for i in 0..<min(limit, 6) where orig[i].letterCount >= 3 && !skip.matches(fold[i]) {
            return properCase(orig[i].collapsedSpaces)
        }
        return nil
    }

    private func courtName() -> String? {
        guard let m = Re("\\bsad\\s+(rejonowy|okregowy|apelacyjny|najwyzszy)\\b[^\\n]*").first(in: fullF) else { return nil }
        var name = full.sub(m.range)
        if let cut = Re("(\\s*,|\\s+wydzial|\\s+sygn|\\s+w\\s+skladzie|\\s+dnia|\\s+z\\s+dnia|\\s+\\d)").first(in: Fold.fold(name)) {
            name = (name as NSString).substring(to: cut.range.location)
        }
        let words = properCase(name.collapsedSpaces).split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        let genitive = ["rejonowy": "Rejonowego", "okregowy": "Okręgowego", "apelacyjny": "Apelacyjnego", "najwyzszy": "Najwyższego"]
        let rest = words.dropFirst(2).joined(separator: " ")
        let adjective = genitive[Fold.fold(words[1])] ?? words[1]
        return Polish.restoreDiacritics(("Sądu \(adjective) " + rest).trimmed)
    }

    /// „I C 123/24", „XII GC 45/23" — cyfry rzymskie wielkimi literami, reszta jak w oryginale.
    private func signature(_ raw: String) -> String {
        var s = raw.collapsedSpaces.replacingOccurrences(of: " / ", with: "/")
            .replacingOccurrences(of: " /", with: "/").replacingOccurrences(of: "/ ", with: "/")
        var parts = s.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return raw }
        parts[0] = parts[0].uppercased()
        if parts.count > 1, parts[1].lowercased() == parts[1] { parts[1] = parts[1].capitalizedFirst }
        s = parts.joined(separator: " ")
        return s
    }

    /// Nazwy własne pisane WERSALIKAMI → „Wersalikami", z małymi spójnikami.
    private func properCase(_ s: String) -> String {
        guard s.upperRatio > 0.6 else { return Polish.restoreDiacritics(s) }
        let small: Set<String> = ["w", "we", "i", "z", "ze", "dla", "na", "od", "do", "o"]
        let keep: Set<String> = ["s.a.", "sa", "s.c.", "sp.j.", "pko", "bp", "ii", "iii", "iv"]
        var out = s.split(separator: " ").enumerated().map { idx, w -> String in
            let original = String(w)
            let word = original.lowercased()
            if keep.contains(word) { return word.uppercased() }
            if idx > 0 && small.contains(word) { return word }
            // Krótkie skrótowce (PZU, ING, ZUS) zostają wersalikami.
            if original.letterCount <= 3 && original.letterCount >= 2 && original == original.uppercased() { return original }
            return word.split(separator: "-", omittingEmptySubsequences: false).map { String($0).capitalizedFirst }.joined(separator: "-")
        }.joined(separator: " ")
        out = out.replacingOccurrences(of: "Sp. z O.o.", with: "sp. z o.o.")
            .replacingOccurrences(of: "Sp. z o.o.", with: "sp. z o.o.")
        return Polish.restoreDiacritics(out)
    }

    private func amount(_ re: Re) -> String? {
        guard let m = re.first(in: fullF) else { return nil }
        let raw = fullF.sub(m.range(at: 1)).replacingOccurrences(of: " ", with: "")
        guard raw.count > 3 else { return nil }
        let fracStart = raw.index(raw.endIndex, offsetBy: -2)
        let intPart = raw[..<raw.index(before: fracStart)].replacingOccurrences(of: ".", with: "")
        // Separator tysięcy: spacja nierozdzielająca, jak w pismach.
        var grouped = ""
        for (n, ch) in intPart.reversed().enumerated() {
            if n > 0 && n % 3 == 0 { grouped.append("\u{00A0}") }
            grouped.append(ch)
        }
        return String(grouped.reversed()) + "," + raw[fracStart...] + " zł"
    }

    // MARK: - Data

    private static let goodBefore = Re("(z\\s+dnia|dnia|w\\s+dniu|data\\s+(wystawienia|dokumentu|sporzadzenia)|wystawion[aoy]?(\\s+w\\s+dniu|\\s+dnia)?|sporzadzon[aoy]?|zawart[aoy]\\s+w\\s+dniu)\\s*[:.]?\\s*$")
    private static let okBefore = Re("(data\\s+(sprzedazy|transakcji|operacji|zlecenia|ksiegowania|wykonania|nadania|wplywu|realizacji)|wyslano|sent|date|data)\\s*[:.]?\\s*$")
    private static let placeDate = Re("^\\W*[a-z][a-z\\- ]{2,30},\\s*(dnia|dn\\.)?\\s*$")
    private static let badBefore = Re("(ur\\.|urodz|pesel|termin|platnosc|platnosci|zaplaty\\s+do|wazn|do\\s+dnia|od\\s+dnia|wydan[yao]|ustaw[ay]?\\s+z\\s+dnia|rozporzadzeni[ae][^\\n]*z\\s+dnia|obowiazuj)[^\\n]{0,12}$")
    private static let badAfter = Re("^[^\\n]{0,40}(kodeks|ustaw|dz\\.?\\s*u|o\\s+ochronie|prawo\\s+(budowlane|bankowe|upadlosciowe))")

    private func pickDate() -> (DMY?, Bool) {
        let found = PLDate.findAll(in: fullF)
        guard !found.isEmpty else { return (nil, false) }
        let ns = fullF as NSString
        var best: (DMY, Double)?
        for f in found {
            let nl = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: f.range.location)).location
            let from = nl == NSNotFound ? 0 : nl + 1
            let sameLineBefore = ns.substring(with: NSRange(location: from, length: f.range.location - from))
            let beforeStart = max(0, f.range.location - 45)
            let before = ns.substring(with: NSRange(location: beforeStart, length: f.range.location - beforeStart))
            let afterLen = min(60, ns.length - (f.range.location + f.range.length))
            let after = ns.substring(with: NSRange(location: f.range.location + f.range.length, length: afterLen))

            var s = 2 * (1 - Double(f.range.location) / Double(max(ns.length, 1)))
            if Self.goodBefore.matches(before) { s += 5 }
            else if Self.okBefore.matches(before) { s += 4 }
            if Self.placeDate.matches(sameLineBefore) { s += 6 }
            if Self.badBefore.matches(before) { s -= 8 }
            if Self.badAfter.matches(after) { s -= 8 }
            if best == nil || s > best!.1 { best = (f.date, s) }
        }
        let distinct = Set(found.map(\.date)).count
        return (best?.0, (best?.1 ?? 0) < 1 && distinct >= 2)
    }
}
