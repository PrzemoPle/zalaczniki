// Renderuje prawdziwe widoki aplikacji poza ekranem do PNG (jasny i ciemny motyw),
// żeby obejrzeć interfejs bez uprawnień do nagrywania ekranu.
// Budowa: scripts/testuj.sh
import AppKit
import SwiftUI

@main
struct Snapshot {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ZAL_SNAPSHOT_OUT"] ?? ".")
        // Lista plików ze stdin — ścieżki w argv przechwyciłby ContentView (otwieranie przy starcie).
        let files = (readLine(strippingNewline: true) ?? "").split(separator: "|").map { URL(fileURLWithPath: String($0)) }

        Task { @MainActor in
            let model = AppModel()
            model.add(files)
            while model.busyCount > 0 { try? await Task.sleep(nanoseconds: 200_000_000) }

            func shot(_ name: String, _ dark: Bool, size: NSSize = NSSize(width: 1180, height: 780), _ view: some View) {
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let host = NSHostingView(rootView: view.environmentObject(model))
                host.frame = NSRect(origin: .zero, size: size)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                // Własne okno można zrzucić bez uprawnień; listy AppKit nie rysują się w cacheDisplay.
                window.setFrameOrigin(NSPoint(x: 40, y: 40))
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                var rep: NSBitmapImageRep
                if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                    rep = NSBitmapImageRep(cgImage: cg)
                } else {
                    rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: rep)
                }
                window.orderOut(nil)
                try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name)-\(dark ? "ciemny" : "jasny").png"))
            }

            // Dokument do sprawdzenia i dokument pewny.
            model.selection = model.items.first { $0.needsReview }?.id
            for dark in [false, true] { shot("1-do-sprawdzenia", dark, ContentView()) }
            model.selection = model.items.first?.id
            shot("2-akt", false, ContentView())
            model.pane = .list
            for dark in [false, true] { shot("3-lista", dark, ContentView()) }
            model.removeAll()
            shot("4-pusty", false, size: NSSize(width: 900, height: 600), ContentView())
            shot("5-ustawienia", false, size: NSSize(width: 520, height: 470), SettingsView())
            print("Zapisano do \(out.path)")
            exit(0)
        }
        app.run()
    }
}
