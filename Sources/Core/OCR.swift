import AppKit
import ImageIO
import PDFKit
import Vision

/// Jedna linia tekstu. `box` w układzie znormalizowanym 0–1, początek w lewym górnym rogu.
struct TextLine {
    var text: String
    var box: CGRect?
    var confidence: Float
}

struct PageText {
    var lines: [TextLine]
    var fromPDFLayer: Bool
    var meanConfidence: Float
    /// Jak Vision musiała obrócić stronę, żeby ją przeczytać (skan bokiem).
    var orientation: CGImagePropertyOrientation = .up
    var plainText: String { lines.map(\.text).joined(separator: "\n") }
}

struct LoadedPage {
    var image: CGImage
    var pageCount: Int
    var embeddedText: String?
}

enum LoadError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Nie udało się otworzyć pliku." }
}

enum PageLoader {
    static let supportedExtensions: Set<String> = ["pdf", "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]

    /// Renderuje wskazaną stronę (od 0) tak, by dłuższy bok miał `maxSide` pikseli.
    static func load(_ url: URL, page index: Int, maxSide: CGFloat = 2400) throws -> LoadedPage {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url), doc.pageCount > 0,
                  let page = doc.page(at: min(index, doc.pageCount - 1)) else { throw LoadError.unreadable }
            let image = try render(page, maxSide: maxSide)
            return LoadedPage(image: image, pageCount: doc.pageCount, embeddedText: page.string)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw LoadError.unreadable }
        let count = max(CGImageSourceGetCount(src), 1)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // uwzględnia orientację EXIF ze zdjęć
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, min(index, count - 1), opts as CFDictionary) else {
            throw LoadError.unreadable
        }
        return LoadedPage(image: image, pageCount: count, embeddedText: nil)
    }

    private static func render(_ page: PDFPage, maxSide: CGFloat) throws -> CGImage {
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let scale = maxSide / max(size.width, size.height, 1)
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw LoadError.unreadable }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.transform(for: .mediaBox))
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { throw LoadError.unreadable }
        return image
    }

    // MARK: Podglądy

    /// Obraz obrócony do pozycji czytania (orientacja jak w EXIF / Vision).
    static func upright(_ image: CGImage, _ o: CGImagePropertyOrientation) -> CGImage {
        guard o == .right || o == .left || o == .down else { return image }
        let swap = o != .down
        let w = swap ? image.height : image.width, h = swap ? image.width : image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        switch o {
        case .right: ctx.translateBy(x: 0, y: CGFloat(h)); ctx.rotate(by: -.pi / 2)
        case .left: ctx.translateBy(x: CGFloat(w), y: 0); ctx.rotate(by: .pi / 2)
        default: ctx.translateBy(x: CGFloat(w), y: CGFloat(h)); ctx.rotate(by: .pi)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    static func jpeg(_ image: CGImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
        let scaled = downscale(image, maxSide: maxSide)
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    static func downscale(_ image: CGImage, maxSide: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxSide else { return image }
        let s = maxSide / longest
        let w = Int(CGFloat(image.width) * s), h = Int(CGFloat(image.height) * s)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}

enum OCR {
    /// Na macOS 12 Vision nie zna polskiego — wtedy czytamy „po łacińsku"
    /// bez korekty językowej, która psułaby polskie słowa.
    static func request() -> VNRecognizeTextRequest {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .accurate
        if let forced = ProcessInfo.processInfo.environment["ZAL_OCR_REVISION"], let rev = Int(forced) {
            r.revision = rev   // do testów: 2 = zachowanie jak na macOS 12
        }
        let supported = (try? r.supportedRecognitionLanguages()) ?? []
        if supported.contains("pl-PL") {
            r.recognitionLanguages = ["pl-PL", "en-US"]
            r.usesLanguageCorrection = true
        } else {
            r.recognitionLanguages = ["de-DE", "fr-FR", "en-US"].filter { supported.contains($0) }
            r.usesLanguageCorrection = false
        }
        return r
    }

    static var polishSupported: Bool {
        ((try? request().supportedRecognitionLanguages()) ?? []).contains("pl-PL")
    }

    static func recognize(_ image: CGImage) -> PageText {
        var best = run(image, orientation: .up)
        // Strona leży bokiem: Vision czyta wtedy tylko strzępy, a ramki linii są „wysokie".
        let boxes = best.lines.compactMap(\.box)
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        // A4 zeskanowane bokiem daje obraz poziomy — wtedy też sprawdzamy obroty.
        let sideways = aspect < 0.87
            || (!boxes.isEmpty && boxes.filter { $0.height * aspect > $0.width * 1.5 }.count * 2 > boxes.count)
        // Prawie nic nie wyszło albo tekst stoi pionowo — próbujemy obrotów.
        if best.plainText.letterCount < 60 || sideways {
            let tries: [CGImagePropertyOrientation] = sideways ? [.right, .left] : [.right, .left, .down]
            for o in tries {
                let attempt = run(image, orientation: o)
                let need = sideways ? best.plainText.letterCount + best.plainText.letterCount / 5 : best.plainText.letterCount * 2 + 20
                if attempt.plainText.letterCount > need { best = attempt; best.orientation = o }
            }
        }
        return best
    }

    /// Pasy strony (układ Vision: początek w lewym dolnym rogu), od góry, z zakładką.
    /// Cała strona naraz potrafi „zawiesić" Vision na minutę przy zaszumionym skanie
    /// z drobnym drukiem i nic nie zwrócić; pasy czyta się szybko i pewnie.
    private static let strips: [CGRect] = [
        CGRect(x: 0, y: 0.62, width: 1, height: 0.38),
        CGRect(x: 0, y: 0.29, width: 1, height: 0.37),
        CGRect(x: 0, y: 0, width: 1, height: 0.33),
    ]

    private static func run(_ image: CGImage, orientation: CGImagePropertyOrientation) -> PageText {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        var lines: [TextLine] = []
        for roi in strips {
            let req = request()
            req.regionOfInterest = roi
            try? handler.perform([req])
            for o in req.results ?? [] {
                guard let top = o.topCandidates(1).first else { continue }
                // Współrzędne wyniku są względem pasa — przeliczamy na całą stronę.
                let r = o.boundingBox
                let b = CGRect(x: roi.minX + r.minX * roi.width, y: roi.minY + r.minY * roi.height,
                               width: r.width * roi.width, height: r.height * roi.height)
                let line = TextLine(text: Fold.sanitize(top.string),
                                    box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height),
                                    confidence: top.confidence)
                if let k = lines.firstIndex(where: { isDuplicate($0, line) }) {
                    // Linia przecięta granicą pasa bywa odczytana częściowo — zostaje pełniejsza wersja.
                    if line.text.count > lines[k].text.count { lines[k] = line }
                } else {
                    lines.append(line)
                }
            }
        }
        lines = orderReadingWise(lines)
        let mean = lines.isEmpty ? 0 : lines.map(\.confidence).reduce(0, +) / Float(lines.count)
        return PageText(lines: lines, fromPDFLayer: false, meanConfidence: mean)
    }

    /// Ta sama linia odczytana w dwóch zachodzących na siebie pasach.
    private static func isDuplicate(_ a: TextLine, _ b: TextLine) -> Bool {
        guard let x = a.box, let y = b.box else { return false }
        let inter = x.intersection(y)
        guard !inter.isNull else { return false }
        let overlap = (inter.width * inter.height) / min(x.width * x.height, y.width * y.height)
        return overlap > 0.4 || (abs(x.midY - y.midY) < min(x.height, y.height) * 0.6 && Fold.fold(a.text) == Fold.fold(b.text))
    }

    /// Wiersze od góry do dołu, a w obrębie wiersza od lewej do prawej.
    private static func orderReadingWise(_ lines: [TextLine]) -> [TextLine] {
        let sorted = lines.sorted { ($0.box?.midY ?? 0) < ($1.box?.midY ?? 0) }
        var rows: [[TextLine]] = []
        for line in sorted {
            if let last = rows.last?.last, let a = last.box, let b = line.box,
               abs(a.midY - b.midY) < min(a.height, b.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { ($0.box?.minX ?? 0) < ($1.box?.minX ?? 0) } }
    }

    /// Tekst z warstwy PDF (dokumenty „cyfrowe" albo skany z OCR skanera).
    static func fromEmbedded(_ text: String?) -> PageText? {
        guard let text, text.letterCount >= 80 else { return nil }
        let lines = Fold.sanitize(text).components(separatedBy: .newlines)
            .map { $0.trimmed }.filter { !$0.isEmpty }
            .map { TextLine(text: $0, box: nil, confidence: 1) }
        return PageText(lines: lines, fromPDFLayer: true, meanConfidence: 1)
    }
}
