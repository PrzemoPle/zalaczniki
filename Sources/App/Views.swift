import SwiftUI
import UniformTypeIdentifiers

// MARK: - Okno

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    // @State to w SDK macOS 27 makro dostępne tylko z Xcode — używamy typu State wprost.
    private let dropState = State(initialValue: false)
    private var dropTargeted: Bool { dropState.wrappedValue }

    var body: some View {
        Group {
            if model.items.isEmpty {
                EmptyStateView(targeted: dropTargeted)
            } else {
                NavigationView {
                    SidebarView()
                    DetailArea()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 580)
        .onDrop(of: [UTType.fileURL], isTargeted: dropState.projectedValue) { providers in
            model.handleDrop(providers)
            return true
        }
        .overlay(dropOverlay)
        .overlay(alignment: .bottom) { ToastView() }
        .toolbar { WindowToolbar() }
        .onAppear {
            // Pliki podane przy uruchomieniu (open -a Załączniki plik.pdf …).
            let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
            if !paths.isEmpty { model.add(paths.map { URL(fileURLWithPath: $0) }) }
        }
    }

    @ViewBuilder private var dropOverlay: some View {
        if dropTargeted && !model.items.isEmpty {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.06)))
                .overlay(Label("Upuść, aby dodać do listy", systemImage: "plus.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.accentColor))
                .padding(10)
                .allowsHitTesting(false)
        }
    }
}

struct WindowToolbar: ToolbarContent {
    @EnvironmentObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: model.openPanel) {
                Label("Dodaj pliki", systemImage: "plus")
            }
            .help("Dodaj skany (⌘O) — możesz też przeciągnąć je na okno")
        }
        ToolbarItem(placement: .principal) {
            Picker("Widok", selection: $model.pane) {
                ForEach(Pane.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .disabled(model.items.isEmpty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Zapisz listę jako .txt…", action: model.saveList)
                Divider()
                Button("Sortuj według nazw plików", action: model.sortByName)
                Button("Sortuj według dat dokumentów", action: model.sortByDate)
                Divider()
                Button("Usuń wszystkie z listy", action: model.removeAll)
            } label: {
                Label("Więcej", systemImage: "ellipsis.circle")
            }
            .disabled(model.items.isEmpty)
            .help("Zapis do pliku i porządkowanie listy")

            Button(action: model.copyList) {
                Label("Kopiuj listę", systemImage: "doc.on.clipboard")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(model.items.isEmpty)
            .help("Skopiuj gotową listę załączników do schowka (⇧⌘C)")
        }
    }
}

// MARK: - Pusty stan

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel
    let targeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "doc.on.doc")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(targeted ? .accentColor : .secondary)
            VStack(spacing: 8) {
                Text("Przeciągnij tutaj skany załączników")
                    .font(.title2.weight(.semibold))
                Text("PDF, JPG, PNG albo HEIC — pojedyncze pliki lub cały folder. Program odczyta pierwszą stronę każdego dokumentu i zaproponuje opis do listy załączników pozwu.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Wybierz pliki…", action: model.openPanel)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Label(model.aiMode == .off ? "Skany są odczytywane wyłącznie na tym komputerze."
                                       : "Włączony opis przez AI — pierwsze strony trafią do Claude (Anthropic).",
                  systemImage: model.aiMode == .off ? "lock" : "sparkles")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [9, 6]))
                .background(RoundedRectangle(cornerRadius: 16).fill(targeted ? Color.accentColor.opacity(0.05) : .clear))
                .padding(24)
        )
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}

// MARK: - Lista po lewej

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.items) { item in
                AttachmentRow(item: item, number: model.number(of: item.id), line: model.line(for: item))
                    .tag(item.id)
                    .contextMenu {
                        Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        Button("Odczytaj ponownie") { model.reanalyze(item.id) }
                        Divider()
                        Button("Usuń z listy") { model.remove(item.id) }
                    }
            }
            .onMove(perform: model.move)
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let id = model.selection { model.remove(id) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter() }
        .frame(minWidth: 320, idealWidth: 360)
    }
}

struct AttachmentRow: View {
    let item: Attachment
    let number: Int
    let line: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Thumbnail(image: item.thumbnail)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(number).")
                        .font(.body.monospacedDigit())
                        .foregroundColor(.secondary)
                    Text(rowText)
                        .foregroundColor(item.title.isEmpty && item.isBusy ? .secondary : .primary)
                        .lineLimit(3)
                }
                Text(item.fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            StatusMark(item: item)
                .frame(width: 18)
        }
        .padding(.vertical, 4)
    }

    private var rowText: String {
        switch item.phase {
        case .waiting where item.title.isEmpty: return "Czeka w kolejce…"
        case .reading where item.title.isEmpty: return "Odczytuję pierwszą stronę…"
        case .failed: return "Nie udało się odczytać pliku"
        default: return line
        }
    }
}

struct Thumbnail: View {
    let image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .textBackgroundColor))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc").foregroundColor(.secondary.opacity(0.6))
            }
        }
        .frame(width: 34, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

struct StatusMark: View {
    let item: Attachment
    var body: some View {
        Group {
            switch item.phase {
            case .waiting:
                Image(systemName: "clock").foregroundColor(.secondary).help("Czeka w kolejce")
            case .reading:
                ProgressView().controlSize(.small).help("Odczytuję")
            case .asking:
                ProgressView().controlSize(.small).help("Pytam AI o opis")
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundColor(.red).help("Nie udało się odczytać pliku")
            case .done:
                if item.needsReview {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).help("Do sprawdzenia")
                } else if item.reviewed {
                    Image(systemName: "checkmark").foregroundColor(.secondary).help("Sprawdzone")
                }
            }
        }
        .font(.system(size: 13))
        .padding(.top, 2)
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if model.busyCount > 0 {
                    ProgressView().controlSize(.small)
                    Text("Odczytuję \(model.items.count - model.busyCount + 1) z \(model.items.count)…")
                        .lineLimit(1)
                } else {
                    Text(plural(model.items.count, "załącznik", "załączniki", "załączników"))
                }
                Spacer()
                if model.reviewCount > 0 {
                    Button(action: model.selectNextToReview) {
                        Label("\(model.reviewCount) do sprawdzenia", systemImage: "exclamationmark.triangle.fill")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                    .help("Przejdź do następnej pozycji do sprawdzenia (⌘G)")
                }
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

// MARK: - Prawa strona

struct DetailArea: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            if model.pane == .list {
                ListPane()
            } else if let item = model.selected {
                DocumentDetail(item: item)
            } else {
                Text("Wybierz załącznik z listy po lewej.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520)
    }
}

struct DocumentDetail: View {
    @EnvironmentObject var model: AppModel
    let item: Attachment

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if case let .failed(message) = item.phase {
                    Banner(kind: .error, title: "Nie udało się odczytać pliku", lines: [message]) {
                        Button("Spróbuj ponownie") { model.reanalyze(item.id) }
                    }
                } else if item.needsReview {
                    Banner(kind: .warning, title: "Do sprawdzenia", lines: item.reasons) {
                        Button("Sprawdzone", action: model.markReviewed)
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("Oznacz jako sprawdzone i przejdź do następnej pozycji (⌘↩)")
                    }
                }
                fields
                resultLine
                if let note = item.aiNote {
                    Label(note, systemImage: "exclamationmark.bubble").font(.callout).foregroundColor(.secondary)
                }
            }
            .padding(20)
            Divider()
            PagePreview(data: item.preview, busy: item.isBusy)
        }
        .id(item.id)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName).font(.headline).lineLimit(1).truncationMode(.middle)
                if item.source == .ai {
                    Label("Opis przygotowała AI — przejrzyj go przed wysłaniem pozwu", systemImage: "sparkles")
                        .font(.caption).foregroundColor(.secondary)
                } else if item.phase == .done {
                    Text(item.pageCount > 1 ? "Opis odczytany ze strony \(item.pageIndex + 1) z \(item.pageCount)" : "Opis odczytany z pierwszej strony")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if item.pageCount > 1 {
                Stepper("Strona \(item.pageIndex + 1) z \(item.pageCount)",
                        onIncrement: { model.reanalyze(item.id, page: item.pageIndex + 1) },
                        onDecrement: { model.reanalyze(item.id, page: item.pageIndex - 1) })
                    .disabled(item.isBusy)
                    .help("Odczytaj opis z innej strony — gdy pierwsza jest np. okładką")
            }
            Menu {
                Button("Otwórz plik") { NSWorkspace.shared.open(item.url) }
                Button("Pokaż w Finderze") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                Divider()
                Button("Odczytaj ponownie") { model.reanalyze(item.id) }
                if model.hasAPIKey {
                    Button("Opisz przez AI") { model.describeWithAI(item.id) }
                }
                Divider()
                Button("Przesuń wyżej") { model.moveSelected(by: -1) }
                Button("Przesuń niżej") { model.moveSelected(by: 1) }
                Divider()
                Button("Usuń z listy") { model.remove(item.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Więcej działań")
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldRow(label: "Opis") {
                TextField("np. Umowa najmu lokalu mieszkalnego", text: model.binding(item.id, \.title))
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "Data") {
                HStack(spacing: 10) {
                    TextField("dd.mm.rrrr", text: model.binding(item.id, \.dateText))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    DateHint(text: item.dateText, style: model.dateStyle)
                }
            }
            FieldRow(label: "Dopisek") {
                TextField("np. Rep. A nr 1234/2019 albo sygn. akt I C 12/24", text: model.binding(item.id, \.detail))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .disabled(item.phase == .reading || item.phase == .asking)
    }

    private var resultLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("W pozwie")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text("\(model.number(of: item.id)). \(model.line(for: item))")
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.045)))
        }
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
            content
        }
    }
}

struct DateHint: View {
    let text: String
    let style: DateStyle
    var body: some View {
        Group {
            if text.trimmed.isEmpty {
                Text("bez daty — w liście pojawi się sam opis")
            } else if let d = PLDate.parseUser(text) {
                Text("→ z dnia \(PLDate.format(d, style: style))")
            } else {
                Text("nie rozpoznaję daty — trafi do listy dosłownie")
                    .foregroundColor(.orange)
            }
        }
        .font(.callout)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
}

struct Banner<Actions: View>: View {
    enum Kind { case warning, error }
    let kind: Kind
    let title: String
    let lines: [String]
    @ViewBuilder let actions: Actions

    var body: some View {
        let tint: Color = kind == .warning ? .orange : .red
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                .foregroundColor(tint)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                ForEach(lines, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}

struct PagePreview: View {
    let data: Data?
    let busy: Bool
    // @State to w SDK macOS 27 makro dostępne tylko z Xcode — używamy typu State wprost.
    private let imageState = State<NSImage?>(initialValue: nil)
    private var image: NSImage? { imageState.wrappedValue }

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image {
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        let width = max(200, min(760, geo.size.width - 48))
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: width)
                            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else if busy {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Odczytuję dokument…").foregroundColor(.secondary)
                }
            } else {
                Text("Brak podglądu").foregroundColor(.secondary)
            }
        }
        .onAppear { imageState.wrappedValue = data.flatMap(NSImage.init(data:)) }
        .onChange(of: data) { imageState.wrappedValue = $0.flatMap(NSImage.init(data:)) }
    }
}

// MARK: - Gotowa lista

struct ListPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                Form {
                    Picker("Numeracja:", selection: $model.numbering) {
                        ForEach(Numbering.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Daty:", selection: $model.dateStyle) {
                        ForEach(DateStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Końce linii:", selection: $model.ending) {
                        ForEach(LineEnding.allCases) { Text($0.label).tag($0) }
                    }
                }
                .frame(width: 330)
                Form {
                    Stepper("Pierwszy numer: \(model.startAt)", value: $model.startAt, in: 1...500)
                    Toggle("Nagłówek „Załączniki:”", isOn: $model.header)
                    Toggle("Opisy małą literą", isOn: $model.lowercaseStart)
                }
            }

            if model.reviewCount > 0 || model.busyCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(model.busyCount > 0
                         ? "Część plików wciąż jest odczytywana."
                         : "\(plural(model.reviewCount, "pozycja czeka", "pozycje czekają", "pozycji czeka")) na sprawdzenie.")
                    if model.reviewCount > 0 {
                        Button("Pokaż", action: model.selectNextToReview).buttonStyle(.link)
                    }
                }
                .font(.callout)
            }

            ScrollView {
                Text(model.renderedList)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))

            HStack {
                Text("Tekst możesz też zaznaczyć i skopiować fragment.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Zapisz jako .txt…", action: model.saveList)
                Button(action: model.copyList) {
                    Label("Kopiuj listę", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(20)
    }
}

// MARK: - Komunikat

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let message = model.toast {
            Label(message, systemImage: "checkmark.circle.fill")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
                .padding(.bottom, 22)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }
}
