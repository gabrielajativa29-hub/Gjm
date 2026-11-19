import Foundation

/// Normaliza texto para comparar sin distinguir mayúsculas ni tildes.
/// La «ñ» se conserva: «año» y «ano» son palabras distintas.
enum TextNormalizer {
    /// Marcador privado que sustituye a la «ñ» mientras se quitan los diacríticos.
    private static let enyeMarker = "\u{F8FF}"

    static func key(_ text: String) -> String {
        let protectedText = text.lowercased()
            .replacingOccurrences(of: "ñ", with: enyeMarker)
        let folded = protectedText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded
            .replacingOccurrences(of: enyeMarker, with: "ñ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Cierto si todas las palabras de `query` aparecen en `text` (en cualquier orden).
    /// Una consulta vacía coincide con todo.
    static func matches(_ text: String, query: String) -> Bool {
        let words = key(query).split(separator: " ")
        if words.isEmpty { return true }
        let haystack = key(text)
        return words.allSatisfy { haystack.contains($0) }
    }
}
