import Foundation
import Security

// MARK: - Opis dokumentu przez Claude (opcjonalnie)

struct AIDescription: Decodable {
    let opis: String
    let data: String
    let dopisek: String
    let pewny: Bool
    let uwagi: String
}

enum AIError: LocalizedError {
    case noKey, http(Int, String), refused, malformed, network(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "Brak klucza API — dodaj go w Ustawieniach."
        case .http(401, _): return "Klucz API został odrzucony — sprawdź go w Ustawieniach."
        case .http(429, _): return "Za dużo zapytań naraz — spróbuj ponownie za chwilę."
        case let .http(code, msg): return "Błąd usługi AI (\(code)): \(msg)"
        case .refused: return "AI odmówiła opisu tego dokumentu."
        case .malformed: return "AI zwróciła nieczytelną odpowiedź."
        case let .network(msg): return "Brak połączenia z usługą AI: \(msg)"
        }
    }
}

enum ClaudeClient {
    static let model = "claude-opus-5-5"

    private static let system = """
    Jesteś asystentem polskiej kancelarii adwokackiej. Dostajesz skan pierwszej strony dokumentu, \
    który będzie załącznikiem do pozwu, oraz tekst odczytany z niego przez OCR (OCR bywa błędny, \
    zwłaszcza w polskich znakach — w razie rozbieżności ufaj obrazowi). Przygotuj pozycję do listy \
    załączników pozwu.

    Pola odpowiedzi:
    - opis: rodzaj dokumentu w mianowniku, zwięźle i po kancelaryjnemu, z polskimi znakami, BEZ daty. \
    Przykłady: „Akt notarialny – umowa sprzedaży", „Faktura VAT nr FV/12/2024", „Paragon fiskalny ze \
    sklepu Biedronka", „Wyrok Sądu Rejonowego w Poznaniu", „Umowa najmu lokalu mieszkalnego", \
    „Wiadomość e-mail", „Pismo PZU SA".
    - data: data wystawienia lub sporządzenia dokumentu w formacie DD.MM.RRRR, a gdy jej nie ma — pusty \
    tekst. Pomiń daty urodzenia, terminy płatności, daty ważności i daty ustaw.
    - dopisek: istotny identyfikator lub uzupełnienie, np. „Rep. A nr 1234/2019", „sygn. akt I C 123/24", \
    „wystawiona przez ABC sp. z o.o.", „na kwotę 1 234,56 zł"; pusty tekst, jeśli nic takiego nie ma.
    - pewny: false, gdy dokument jest nieczytelny, nietypowy albo niejednoznaczny.
    - uwagi: jedno krótkie zdanie, co warto sprawdzić; pusty tekst, gdy pewny = true.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "opis": ["type": "string"],
            "data": ["type": "string"],
            "dopisek": ["type": "string"],
            "pewny": ["type": "boolean"],
            "uwagi": ["type": "string"],
        ],
        "required": ["opis", "data", "dopisek", "pewny", "uwagi"],
        "additionalProperties": false,
    ]

    static func describe(jpeg: Data, ocrText: String, apiKey: String) async throws -> AIDescription {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": system,
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            // Gdy zabezpieczenia modelu odrzucą prośbę, API samo ponawia ją na zalecanym modelu.
            "fallbacks": "default",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": "Tekst z OCR:\n\n" + String(ocrText.prefix(6000))],
                ],
            ]],
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw AIError.network(error.localizedDescription) }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "nieznany błąd"
            throw AIError.http(status, msg)
        }
        if json["stop_reason"] as? String == "refusal" { throw AIError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let payload = text.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIDescription.self, from: payload) else { throw AIError.malformed }
        return result
    }
}

// MARK: - Klucz API w pęku kluczy

enum Keychain {
    private static let service = "pl.plewinscy.zalaczniki"
    private static let account = "anthropic-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var q = baseQuery
        q[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
