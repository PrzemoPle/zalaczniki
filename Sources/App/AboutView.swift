import AppKit
import SwiftUI

/// Dane o wydaniu — z Info.plist, które uzupełnia scripts/build.sh.
enum AppInfo {
    static let name = "Załączniki"
    static let author = "Przemysław Plewiński"
    static let email = "przemyslaw@plewinski.pl"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "wersja deweloperska"
    }

    /// „30 września 2026 r." z klucza ZALDataWydania (RRRR-MM-DD).
    static var releaseDate: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ZALDataWydania") as? String,
              let d = PLDate.parseUser(raw) else { return nil }
        return PLDate.format(d, style: .words)
    }

    static var mailURL: URL {
        let subject = "\(name) \(version) — uwagi".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(email)?subject=\(subject)")!
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text(AppInfo.name)
                    .font(.title.weight(.semibold))
                Text("Wersja \(AppInfo.version)")
                    .foregroundColor(.secondary)
                if let date = AppInfo.releaseDate {
                    Text("Wydana \(date)")
                        .foregroundColor(.secondary)
                }
            }
            Text("Tworzy listę załączników do pozwu na podstawie skanów dokumentów.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            Divider().frame(width: 240)

            VStack(spacing: 4) {
                Text("Autor").font(.caption).foregroundColor(.secondary)
                Text(AppInfo.author).fontWeight(.medium)
                Link(AppInfo.email, destination: AppInfo.mailURL)
                    .help("Napisz do autora — uwagi, błędy, pomysły")
            }

            Text("© 2026 \(AppInfo.author) · Licencja MIT")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(minWidth: 380)
    }
}

/// Okno „O aplikacji" z menu programu (na macOS 12 SwiftUI nie otwiera własnych okien na żądanie).
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.title = "O aplikacji \(AppInfo.name)"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
