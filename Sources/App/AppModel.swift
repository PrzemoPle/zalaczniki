import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AIMode: String, CaseIterable, Identifiable {
    case off, flagged, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Wyłączony — skany nie opuszczają komputera"
        case .flagged: return "Tylko dla pozycji, których program nie rozpoznał"
        case .all: return "Dla wszystkich dokumentów"
        }
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case document, list
    var id: String { rawValue }
    var label: String { self == .document ? "Dokument" : "Gotowa lista" }
}

struct Attachment: Identifiable {
    enum Phase: Equatable { case waiting, reading, asking, done, failed(String) }
    enum Source { case local, ai }

    let id = UUID()
    let url: URL
    var pageIndex = 0
    var pageCount = 1
    var phase: Phase = .waiting
    var title = ""
    var dateText = ""
    var detail = ""
    var reasons: [String] = []
    var reviewed = false
    var ocrText = ""
    var thumbnail: NSImage?
    var preview: Data?
    var source: Source = .local
    var aiNote: String?

    var fileName: String { url.lastPathComponent }
    var isBusy: Bool { phase == .waiting || phase == .reading || phase == .asking }
    var needsReview: Bool {
        if case .failed = phase { return !reviewed }
        return phase == .done && !reviewed && !reasons.isEmpty
    }
    var entry: ListEntry { ListEntry(title: title, dateText: dateText, detail: detail, fallbackName: fileName) }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [Attachment] = []
    @Published var selection: UUID?
    @Published var pane: Pane = .document
    @Published var toast: String?

    // Ustawienia listy i AI — pamiętane między uruchomieniami.
    @Published var numbering: Numbering { didSet { save(numbering.rawValue, "numbering") } }
    @Published var dateStyle: DateStyle { didSet { save(dateStyle.rawValue, "dateStyle") } }
    @Published var ending: LineEnding { didSet { save(ending.rawValue, "ending") } }
    @Published var startAt: Int { didSet { save(startAt, "startAt") } }
    @Published var header: Bool { didSet { save(header, "header") } }
    @Published var lowercaseStart: Bool { didSet { save(lowercaseStart, "lowercaseStart") } }
    @Published var aiMode: AIMode { didSet { save(aiMode.rawValue, "aiMode") } }
    @Published private(set) var hasAPIKey = Keychain.load() != nil

    private var queue: [UUID] = []
    private var running = 0
    // MacBook Air 2015 ma dwa rdzenie — jeden dokument naraz wystarczy, a okno zostaje płynne.
    private let parallel = ProcessInfo.processInfo.activeProcessorCount >= 6 ? 2 : 1
    private var toastTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        numbering = Numbering(rawValue: d.string(forKey: "numbering") ?? "") ?? .dot
        dateStyle = DateStyle(rawValue: d.string(forKey: "dateStyle") ?? "") ?? .words
        ending = LineEnding(rawValue: d.string(forKey: "ending") ?? "") ?? .semicolon
        startAt = max(1, d.integer(forKey: "startAt"))
        header = d.object(forKey: "header") as? Bool ?? true
        lowercaseStart = d.bool(forKey: "lowercaseStart")
        aiMode = AIMode(rawValue: d.string(forKey: "aiMode") ?? "") ?? .off
    }

    private func save(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: key) }

    var options: ListOptions {
        ListOptions(numbering: numbering, dateStyle: dateStyle, ending: ending, startAt: startAt,
                    header: header, lowercaseStart: lowercaseStart)
    }
    var renderedList: String { ListFormatter.render(items.map(\.entry), options: options) }
    var reviewCount: Int { items.filter(\.needsReview).count }
    var busyCount: Int { items.filter(\.isBusy).count }
    var selected: Attachment? { items.first { $0.id == selection } }

    func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }
    func number(of id: UUID) -> Int { (index(id) ?? 0) + startAt }

    func line(for item: Attachment) -> String {
        ListFormatter.describe(item.entry, style: dateStyle, lowercaseStart: lowercaseStart)
    }

    /// Edycja pola przez użytkownika = pozycja sprawdzona.
    func binding(_ id: UUID, _ key: WritableKeyPath<Attachment, String>) -> Binding<String> {
        Binding(get: { [weak self] in
            self?.items.first { $0.id == id }?[keyPath: key] ?? ""
        }, set: { [weak self] value in
            guard let self, let i = self.index(id), self.items[i][keyPath: key] != value else { return }
            self.items[i][keyPath: key] = value
            self.items[i].reviewed = true
        })
    }

    // MARK: - Dodawanie plików

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.pdf, .image]
        panel.prompt = "Dodaj"
        panel.message = "Wybierz skany załączników albo cały folder."
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in self?.add(urls) }
    }

    func add(_ urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let f = e?.nextObject() as? URL { files.append(f) }
            } else {
                files.append(url)
            }
        }
        let known = Set(items.map { $0.url.standardizedFileURL })
        let fresh = files
            .filter { PageLoader.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .filter { !known.contains($0.standardizedFileURL) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let skipped = files.count - fresh.count
        guard !fresh.isEmpty else {
            if !files.isEmpty { show("Te pliki są już na liście albo to nie skany (PDF, JPG, PNG, HEIC).") }
            return
        }
        let newItems = fresh.map { Attachment(url: $0) }
        items.append(contentsOf: newItems)
        if selection == nil { selection = newItems.first?.id }
        queue.append(contentsOf: newItems.map(\.id))
        if skipped > 0 { show("Pominięto \(plural(skipped, "plik", "pliki", "plików")) — duplikaty albo nieobsługiwany format.") }
        pump()
    }

    // MARK: - Przetwarzanie

    private func pump() {
        while running < parallel, !queue.isEmpty {
            let id = queue.removeFirst()
            guard index(id) != nil else { continue }
            running += 1
            Task {
                await process(id)
                running -= 1
                pump()
            }
        }
    }

    private struct Analysis {
        var pageCount: Int
        var text: PageText
        var suggestion: Suggestion
        var preview: Data?
        var thumbnail: CGImage
    }

    nonisolated private static func analyze(_ url: URL, page: Int) throws -> Analysis {
        let loaded = try PageLoader.load(url, page: page)
        let text = OCR.fromEmbedded(loaded.embeddedText) ?? OCR.recognize(loaded.image)
        // Skan zeskanowany bokiem pokazujemy (i wysyłamy do AI) już obrócony.
        let page = PageLoader.upright(loaded.image, text.orientation)
        return Analysis(pageCount: loaded.pageCount,
                        text: text,
                        suggestion: Classifier.classify(text),
                        preview: PageLoader.jpeg(page, maxSide: 1568, quality: 0.75),
                        thumbnail: PageLoader.downscale(page, maxSide: 120))
    }

    private func process(_ id: UUID, forceAI: Bool = false) async {
        guard let i = index(id) else { return }
        items[i].phase = .reading
        let url = items[i].url, page = items[i].pageIndex
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Analysis, Error> in
            Result { try Self.analyze(url, page: page) }
        }.value

        guard let j = index(id) else { return }
        switch result {
        case let .failure(error):
            items[j].phase = .failed(error.localizedDescription)
            return
        case let .success(a):
            let s = a.suggestion
            items[j].pageCount = a.pageCount
            items[j].ocrText = a.text.plainText
            items[j].preview = a.preview
            items[j].thumbnail = NSImage(cgImage: a.thumbnail, size: NSSize(width: a.thumbnail.width, height: a.thumbnail.height))
            items[j].title = s.title
            items[j].dateText = s.date.map(PLDate.shortNumeric) ?? ""
            items[j].detail = s.detail
            items[j].reasons = s.reasons
            items[j].source = .local
            items[j].reviewed = false
            items[j].aiNote = nil

            let wantsAI = forceAI || aiMode == .all || (aiMode == .flagged && !s.reasons.isEmpty)
            if wantsAI, let jpeg = a.preview {
                await askAI(id, jpeg: jpeg, text: a.text.plainText)
            }
            if let k = index(id) { items[k].phase = .done }
        }
    }

    private func askAI(_ id: UUID, jpeg: Data, text: String) async {
        guard let key = Keychain.load() else {
            if let k = index(id) { items[k].aiNote = AIError.noKey.localizedDescription }
            return
        }
        if let k = index(id) { items[k].phase = .asking }
        do {
            let ai = try await ClaudeClient.describe(jpeg: jpeg, ocrText: text, apiKey: key)
            guard let k = index(id) else { return }
            items[k].title = ai.opis
            items[k].dateText = PLDate.parseUser(ai.data).map(PLDate.shortNumeric) ?? ai.data
            items[k].detail = ai.dopisek
            items[k].reasons = ai.pewny ? [] : [ai.uwagi.isEmpty ? "AI nie jest pewna tego opisu." : ai.uwagi]
            items[k].source = .ai
        } catch {
            if let k = index(id) { items[k].aiNote = error.localizedDescription }
        }
    }

    func reanalyze(_ id: UUID, page: Int? = nil) {
        guard let i = index(id), !items[i].isBusy else { return }
        if let page { items[i].pageIndex = max(0, min(page, items[i].pageCount - 1)) }
        items[i].phase = .waiting
        queue.append(id)
        pump()
    }

    func describeWithAI(_ id: UUID) {
        guard let i = index(id), !items[i].isBusy else { return }
        items[i].phase = .waiting
        running += 1
        Task {
            await process(id, forceAI: true)
            running -= 1
            pump()
        }
    }

    // MARK: - Porządkowanie

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func moveSelected(by offset: Int) {
        guard let id = selection, let i = index(id) else { return }
        let target = i + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(i, target)
    }

    func sortByName() {
        items.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    /// Chronologicznie; pozycje bez rozpoznanej daty na końcu, w dotychczasowej kolejności.
    func sortByDate() {
        let keyed = items.enumerated().map { ($0.offset, $0.element, PLDate.parseUser($0.element.dateText)) }
        items = keyed.sorted { a, b in
            switch (a.2, b.2) {
            case let (x?, y?): return x == y ? a.0 < b.0 : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.0 < b.0
            }
        }.map(\.1)
    }

    func remove(_ id: UUID) {
        guard let i = index(id) else { return }
        items.remove(at: i)
        queue.removeAll { $0 == id }
        if selection == id { selection = items.indices.contains(i) ? items[i].id : items.last?.id }
    }

    func removeAll() {
        items.removeAll()
        queue.removeAll()
        selection = nil
        pane = .document
    }

    func markReviewed() {
        guard let id = selection, let i = index(id) else { return }
        items[i].reviewed = true
        selectNextToReview()
    }

    func selectNextToReview() {
        guard !items.isEmpty else { return }
        let start = selection.flatMap(index) ?? -1
        let order = Array(items.indices.dropFirst(start + 1)) + Array(items.indices.prefix(start + 1))
        if let next = order.first(where: { items[$0].needsReview }) {
            selection = items[next].id
            pane = .document
        }
    }

    // MARK: - Eksport

    func copyList() {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(renderedList, forType: .string)
        var message = "Skopiowano listę — \(plural(items.count, "pozycja", "pozycje", "pozycji"))."
        if reviewCount > 0 { message += " \(reviewCount) wciąż do sprawdzenia." }
        show(message)
    }

    func saveList() {
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Załączniki.txt"
        panel.prompt = "Zapisz"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try renderedList.write(to: url, atomically: true, encoding: .utf8)
            show("Zapisano \(url.lastPathComponent).")
        } catch {
            show("Nie udało się zapisać pliku: \(error.localizedDescription)")
        }
    }

    // MARK: - Klucz API

    func saveAPIKey(_ key: String) {
        let k = key.trimmed
        guard !k.isEmpty else { return }
        hasAPIKey = Keychain.save(k)
    }

    func deleteAPIKey() {
        Keychain.delete()
        hasAPIKey = false
    }

    // MARK: - Komunikaty

    func show(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }
}

/// Polska odmiana liczebników: 1 plik, 2 pliki, 5 plików, 22 pliki, 12 plików.
func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let word: String
    if n == 1 { word = one }
    else if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { word = few }
    else { word = many }
    return "\(n) \(word)"
}
