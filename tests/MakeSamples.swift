// Generuje syntetyczne „skany" polskich dokumentów do testów rozpoznawania.
// Wszystkie dane są zmyślone. Uruchom: swift tests/MakeSamples.swift tests/samples
import AppKit
import PDFKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tests/samples")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct B {
    var text: String
    var size: CGFloat = 22
    var bold = false
    var align: NSTextAlignment = .left
    var x: CGFloat = 0.1      // lewy margines (ułamek szerokości)
    var w: CGFloat = 0.8      // szerokość bloku
    var sameRow = false       // postaw obok poprzedniego bloku
    var gap: CGFloat = 14
}

func page(_ blocks: [B], width: Int = 1654, height: Int = 2339, tilt: CGFloat = 0.6, noise: Bool = true) -> NSImage {
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    NSColor(white: 0.97, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    ctx.rotate(by: tilt * .pi / 180)
    ctx.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
    var y = CGFloat(height) * 0.94
    var lastTop = y
    for b in blocks {
        let para = NSMutableParagraphStyle()
        para.alignment = b.align
        para.lineSpacing = 4
        let font = NSFont(name: b.bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT", size: b.size * 2) ?? .systemFont(ofSize: b.size * 2)
        let s = NSAttributedString(string: b.text, attributes: [.font: font, .paragraphStyle: para,
                                                                .foregroundColor: NSColor(white: 0.12, alpha: 1)])
        let bw = CGFloat(width) * b.w
        let bounds = s.boundingRect(with: NSSize(width: bw, height: 3000), options: [.usesLineFragmentOrigin])
        let top = b.sameRow ? lastTop : y
        s.draw(with: NSRect(x: CGFloat(width) * b.x, y: top - bounds.height, width: bw, height: bounds.height),
               options: [.usesLineFragmentOrigin])
        lastTop = top
        y = min(b.sameRow ? y : top - bounds.height - b.gap * 2, top - bounds.height - b.gap * 2)
    }
    if noise {
        var rng = SystemRandomNumberGenerator()
        NSColor(white: 0.55, alpha: 0.5).setFill()
        for _ in 0..<2500 {
            let px = CGFloat.random(in: 0..<CGFloat(width), using: &rng), py = CGFloat.random(in: 0..<CGFloat(height), using: &rng)
            NSRect(x: px, y: py, width: 2, height: 2).fill()
        }
    }
    img.unlockFocus()
    return img
}

func savePNG(_ img: NSImage, _ name: String, rotate90: Bool = false) {
    var cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    if rotate90 {
        let ctx = CGContext(data: nil, width: cg.height, height: cg.width, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.translateBy(x: CGFloat(cg.height), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        cg = ctx.makeImage()!
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    let isJPG = name.hasSuffix(".jpg")
    let data = rep.representation(using: isJPG ? .jpeg : .png, properties: isJPG ? [.compressionFactor: 0.7] : [:])!
    try! data.write(to: outDir.appendingPathComponent(name))
}

/// PDF z samym obrazem — jak ze skanera, bez warstwy tekstu.
func savePDF(_ imgs: [NSImage], _ name: String) {
    let doc = PDFDocument()
    for (i, img) in imgs.enumerated() {
        // Rozmiar w punktach = A4, piksele zostają (jak skan 200 dpi).
        img.size = NSSize(width: 595, height: 842)
        let p = PDFPage(image: img)!
        doc.insert(p, at: i)
    }
    doc.write(to: outDir.appendingPathComponent(name))
}

let body = "Lorem ipsum strony zawarły porozumienie w przedmiocie opisanym poniżej, a każda ze stron oświadcza, że zapoznała się z jego treścią i nie wnosi zastrzeżeń."

savePDF([page([
    B(text: "Repertorium A nr 4521/2019", size: 13, align: .left),
    B(text: "AKT NOTARIALNY", size: 20, bold: true, align: .center),
    B(text: "Dnia dwunastego marca dwa tysiące dziewiętnastego roku (12.03.2019 r.) przed notariuszem Anną Nowak, prowadzącą Kancelarię Notarialną w Poznaniu przy ulicy Półwiejskiej 10, stawili się:", size: 13),
    B(text: "1. Jan Kowalski, syn Piotra i Marii, urodzony 01.02.1970 r., PESEL 70020112345, zamieszkały w Poznaniu,", size: 13),
    B(text: "2. Ewa Zielińska, córka Adama i Teresy, urodzona 15.07.1982 r., PESEL 82071598765.", size: 13),
    B(text: "UMOWA SPRZEDAŻY", size: 16, bold: true, align: .center),
    B(text: "§ 1. Jan Kowalski oświadcza, że jest właścicielem lokalu mieszkalnego numer 5, dla którego Sąd Rejonowy Poznań-Stare Miasto w Poznaniu prowadzi księgę wieczystą KW nr PO1P/00123456/7.", size: 13),
]), page([B(text: body, size: 13)])], "01 akt notarialny.pdf")

savePDF([page([
    B(text: "FAKTURA VAT nr FV/112/2024", size: 20, bold: true, align: .center),
    B(text: "Data wystawienia: 2024-05-14", size: 12, x: 0.55, w: 0.35),
    B(text: "Data sprzedaży: 2024-05-10", size: 12, x: 0.55, w: 0.35),
    B(text: "Sprzedawca:", size: 13, bold: true, x: 0.1, w: 0.35),
    B(text: "Nabywca:", size: 13, bold: true, x: 0.55, w: 0.35, sameRow: true),
    B(text: "Meblex Sp. z o.o.\nul. Fabryczna 3, 61-001 Poznań\nNIP 7781234567", size: 13, x: 0.1, w: 0.35, gap: 20),
    B(text: "Jan Kowalski\nul. Dębowa 7, 60-100 Poznań", size: 13, x: 0.55, w: 0.35, sameRow: true, gap: 20),
    B(text: "Lp. Nazwa towaru       Ilość   Cena netto   VAT   Wartość brutto\n1.  Szafa przesuwna 200 cm   1   4 000,00   23%   4 920,00", size: 12),
    B(text: "Razem do zapłaty: 4 920,00 zł\nTermin płatności: 2024-05-28\nSposób płatności: przelew", size: 12),
])], "02 faktura meble.pdf")

savePNG(page([
    B(text: "Jeronimo Martins Polska S.A.\nBiedronka nr 1234\nul. Głogowska 12, 60-111 Poznań\nNIP 779-10-11-327", size: 12, align: .center, x: 0.3, w: 0.4),
    B(text: "2024-06-03 14:22                  nr wydr. 552/0987", size: 11, x: 0.3, w: 0.4),
    B(text: "PARAGON FISKALNY", size: 14, bold: true, align: .center, x: 0.3, w: 0.4),
    B(text: "Chleb żytni        1 x 5,99   5,99 C\nMasło 200 g        2 x 7,49  14,98 C\nKawa mielona       1 x 29,99 29,99 A\nPłyn do naczyń     1 x 36,49 36,49 A", size: 11, x: 0.3, w: 0.4),
    B(text: "SUMA PLN 87,45", size: 14, bold: true, x: 0.3, w: 0.4),
], width: 1200, height: 2339, tilt: -0.8), "03 paragon.jpg")

savePDF([page([
    B(text: "Sygn. akt I C 1234/23", size: 13, x: 0.1, w: 0.4),
    B(text: "WYROK", size: 20, bold: true, align: .center),
    B(text: "W IMIENIU RZECZYPOSPOLITEJ POLSKIEJ", size: 14, bold: true, align: .center),
    B(text: "Dnia 15 lutego 2024 r.", size: 13, align: .center),
    B(text: "Sąd Rejonowy Poznań-Stare Miasto w Poznaniu, I Wydział Cywilny\nw składzie następującym: Przewodniczący: sędzia Adam Nowicki", size: 13),
    B(text: "po rozpoznaniu w dniu 1 lutego 2024 r. w Poznaniu na rozprawie sprawy z powództwa Jana Kowalskiego przeciwko Meblex Sp. z o.o. o zapłatę", size: 13),
    B(text: "1. zasądza od pozwanego na rzecz powoda kwotę 4 920,00 zł wraz z odsetkami ustawowymi za opóźnienie od dnia 29 maja 2024 r. do dnia zapłaty;", size: 13),
])], "04 wyrok SR.pdf")

savePNG(page([
    B(text: "UMOWA NAJMU LOKALU MIESZKALNEGO", size: 18, bold: true, align: .center),
    B(text: "zawarta w dniu 1 września 2022 r. w Poznaniu pomiędzy:", size: 13, align: .center),
    B(text: "Anną Wiśniewską, zamieszkałą w Poznaniu, legitymującą się dowodem osobistym nr ABC123456, zwaną dalej Wynajmującym,\na\nJanem Kowalskim, zwanym dalej Najemcą.", size: 13),
    B(text: "§ 1. Wynajmujący oświadcza, że jest właścicielem lokalu położonego w Poznaniu przy ul. Dębowej 7/5. Umowa zostaje zawarta na podstawie ustawy z dnia 21 czerwca 2001 r. o ochronie praw lokatorów.", size: 13),
    B(text: body, size: 13),
]), "05 umowa najmu.png")

savePDF([page([
    B(text: "PKO Bank Polski", size: 16, bold: true),
    B(text: "Potwierdzenie wykonania przelewu", size: 18, bold: true),
    B(text: "Data operacji: 2024-01-20\nData księgowania: 2024-01-22\nRachunek nadawcy: 12 1020 4027 0000 1102 0000 0000\nNazwa odbiorcy: Anna Wiśniewska\nRachunek odbiorcy: 45 1140 2004 0000 3002 0000 0000\nTytuł: Czynsz za styczeń 2024\nKwota: 1 500,00 PLN", size: 13),
], tilt: 0.2, noise: false)], "06 przelew czynsz.pdf")

savePNG(page([
    B(text: "Poznań, 3 kwietnia 2024 r.", size: 13, align: .right),
    B(text: "Meblex Sp. z o.o.\nul. Fabryczna 3\n61-001 Poznań", size: 13, x: 0.55, w: 0.35),
    B(text: "OSTATECZNE PRZEDSĄDOWE WEZWANIE DO ZAPŁATY", size: 16, bold: true, align: .center),
    B(text: "Działając w imieniu Jana Kowalskiego, wzywam do zapłaty kwoty 4 920,00 zł tytułem zwrotu ceny za wadliwą szafę, w terminie 7 dni od dnia doręczenia niniejszego wezwania.", size: 13),
]), "07 wezwanie.png")

savePNG(page([
    B(text: "Od: Jan Kowalski <jan.kowalski@example.com>\nWysłano: 12 mar 2024 10:15\nDo: biuro@meblex.example\nTemat: Reklamacja szafy przesuwnej", size: 12),
    B(text: "Dzień dobry,\nzgłaszam reklamację szafy zakupionej na podstawie faktury FV/112/2024. Drzwi przesuwne wypadają z prowadnic.\nZ poważaniem\nJan Kowalski", size: 12),
], noise: false), "08 email.png")

let pismo = [
    B(text: "PZU SA\nal. Jana Pawła II 24\n00-133 Warszawa", size: 12),
    B(text: "Warszawa, 10.10.2023", size: 12, align: .right),
    B(text: "Pan\nJan Kowalski\nul. Dębowa 7/5\n60-100 Poznań", size: 12, x: 0.55, w: 0.35),
    B(text: "Dotyczy: szkoda nr 2023/456/789", size: 12, bold: true),
    B(text: "Szanowny Panie,\nuprzejmie informujemy, że po rozpatrzeniu zgłoszenia szkody przyznaliśmy odszkodowanie w wysokości 2 100,00 zł.", size: 12),
]
savePNG(page(pismo), "09 pismo PZU (obrócone).png", rotate90: true)
savePNG(page(pismo), "13 pismo PZU prosto.png")

// Zdjęcie bez tekstu.
let photo = NSImage(size: NSSize(width: 1600, height: 1200))
photo.lockFocus()
NSGradient(starting: .brown, ending: .darkGray)!.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1200), angle: 60)
NSColor(white: 0.85, alpha: 1).setFill()
NSRect(x: 500, y: 200, width: 600, height: 800).fill()
photo.unlockFocus()
savePNG(photo, "10 zdjecie szafy.jpg")

savePDF([page([
    B(text: "Odpis zwykły księgi wieczystej", size: 18, bold: true, align: .center),
    B(text: "Numer księgi: PO1P/00123456/7\nStan na dzień: 05.07.2024, godz. 12:00\nSąd Rejonowy Poznań-Stare Miasto w Poznaniu, V Wydział Ksiąg Wieczystych", size: 13),
    B(text: "Dział I-O – Oznaczenie nieruchomości\nPołożenie: Poznań, ul. Dębowa 7, lokal nr 5", size: 13),
])], "11 odpis KW.pdf")

savePDF([page([
    B(text: "Sygn. akt V GNc 5678/24", size: 13),
    B(text: "NAKAZ ZAPŁATY", size: 20, bold: true, align: .center),
    B(text: "W POSTĘPOWANIU UPOMINAWCZYM", size: 14, bold: true, align: .center),
    B(text: "Dnia 20 sierpnia 2024 r.\nSąd Rejonowy Poznań-Grunwald i Jeżyce w Poznaniu, V Wydział Gospodarczy", size: 13),
    B(text: "nakazuje pozwanemu, aby zapłacił powodowi kwotę 12 300,00 zł w terminie dwóch tygodni od doręczenia nakazu.", size: 13),
])], "12 nakaz zaplaty.pdf")

print("Gotowe: \(outDir.path)")
