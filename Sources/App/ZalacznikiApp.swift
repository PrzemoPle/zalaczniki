import SwiftUI

@main
struct ZalacznikiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() {
        // Ścieżki z wiersza poleceń obsługujemy sami (ContentView.onAppear). Gdyby AppKit
        // potraktował je jako „otwórz dokument", SwiftUI nie utworzyłby głównego okna.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
    }

    var body: some Scene {
        WindowGroup("Załączniki") {
            ContentView().environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Dodaj pliki…", action: model.openPanel).keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Zapisz listę jako .txt…", action: model.saveList).keyboardShortcut("s")
            }
            CommandMenu("Lista") {
                Button("Kopiuj listę", action: model.copyList).keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button("Oznacz jako sprawdzone", action: model.markReviewed).keyboardShortcut(.return, modifiers: .command)
                Button("Następna do sprawdzenia", action: model.selectNextToReview).keyboardShortcut("g")
                Divider()
                Button("Przesuń wyżej") { model.moveSelected(by: -1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Przesuń niżej") { model.moveSelected(by: 1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Button("Sortuj według nazw plików", action: model.sortByName)
                Button("Sortuj według dat dokumentów", action: model.sortByDate)
                Divider()
                Button("Pokaż dokument") { model.pane = .document }.keyboardShortcut("1")
                Button("Pokaż gotową listę") { model.pane = .list }.keyboardShortcut("2")
            }
        }
        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
