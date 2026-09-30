import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    // @State to w SDK macOS 27 makro dostępne tylko z Xcode — używamy typu State wprost.
    private let draft = State(initialValue: "")
    private var keyDraft: String { draft.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Opis przez AI").font(.headline)
                Text("Program sam rozpoznaje typowe dokumenty bez internetu. Opcjonalnie trudniejsze skany może opisać model Claude firmy Anthropic — wtedy obraz pierwszej strony i odczytany tekst są wysyłane na jej serwery. Rozważ, czy w danej sprawie jest to zgodne z zasadami tajemnicy adwokackiej.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("", selection: $model.aiMode) {
                    ForEach(AIMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Klucz API Anthropic").font(.headline)
                if model.hasAPIKey {
                    HStack {
                        Label("Klucz zapisany w pęku kluczy macOS", systemImage: "key.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Usuń klucz", action: model.deleteAPIKey)
                    }
                } else {
                    HStack {
                        SecureField("sk-ant-…", text: draft.projectedValue)
                            .textFieldStyle(.roundedBorder)
                        Button("Zapisz") {
                            model.saveAPIKey(keyDraft)
                            draft.wrappedValue = ""
                        }
                        .disabled(keyDraft.trimmed.isEmpty)
                    }
                    Link("Jak zdobyć klucz? (console.anthropic.com)", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.callout)
                }
                if model.aiMode != .off && !model.hasAPIKey {
                    Label("Bez klucza opis przez AI nie zadziała — program użyje wyłącznie rozpoznawania lokalnego.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundColor(.orange)
                }
                Text("Koszt to zwykle kilka groszy za dokument.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Divider()

            Label(OCR.polishSupported
                  ? "Rozpoznawanie tekstu: dostępny słownik polski."
                  : "Ta wersja macOS nie ma polskiego słownika OCR — polskie znaki bywają gubione, program to uwzględnia przy rozpoznawaniu.",
                  systemImage: "text.viewfinder")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 520)
    }
}
