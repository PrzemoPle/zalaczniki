// Uruchamia rozpoznawanie na plikach i wypisuje propozycje opisów.
// ZAL_OCR_REVISION=2 udaje OCR z macOS 12 (bez polskiego).
import Foundation

@main
struct Probe {
    static func main() {
        let files = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var entries: [ListEntry] = []
        for url in files {
            let start = Date()
            do {
                let loaded = try PageLoader.load(url, page: 0)
                var text = OCR.fromEmbedded(loaded.embeddedText) ?? OCR.recognize(loaded.image)
                // Najgorszy przypadek z macOS 12: OCR bez żadnych polskich znaków.
                if ProcessInfo.processInfo.environment["ZAL_STRIP_PL"] != nil {
                    let map: [Character: Character] = ["ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z",
                                                       "Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N", "Ó": "O", "Ś": "S", "Ź": "Z", "Ż": "Z"]
                    for i in text.lines.indices { text.lines[i].text = String(text.lines[i].text.map { map[$0] ?? $0 }) }
                }
                let s = Classifier.classify(text)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                print("── \(url.lastPathComponent)  [\(s.kind), \(ms) ms, pewność OCR \(String(format: "%.2f", text.meanConfidence))]")
                print("   opis:    \(s.title)")
                print("   data:    \(s.date.map { PLDate.shortNumeric($0) } ?? "—")")
                print("   dopisek: \(s.detail)")
                if !s.reasons.isEmpty { print("   ⚠︎ " + s.reasons.joined(separator: " | ")) }
                if ProcessInfo.processInfo.environment["ZAL_DUMP"] != nil { print(text.plainText.split(separator: "\n").map { "      » " + $0 }.joined(separator: "\n")) }
                entries.append(ListEntry(title: s.title, dateText: s.date.map { PLDate.shortNumeric($0) } ?? "",
                                         detail: s.detail, fallbackName: url.lastPathComponent))
            } catch {
                print("── \(url.lastPathComponent): BŁĄD \(error.localizedDescription)")
            }
        }
        print("\n" + ListFormatter.render(entries, options: ListOptions()))
    }
}
