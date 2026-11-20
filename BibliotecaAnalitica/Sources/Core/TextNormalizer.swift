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

    /// Clave de búsqueda de una página: une las palabras partidas con guion al final de línea
    /// («pa-\nlabra» → «palabra») y después aplica `key`. El texto original no se modifica.
    static func indexKey(_ text: String) -> String {
        key(dehyphenate(text))
    }

    /// Une «letra-» + salto de línea + «letra minúscula». Si la línea siguiente empieza en
    /// mayúscula, el guion se conserva (nombres compuestos como «Freud-Lacan»).
    static func dehyphenate(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(\\p{L})-[ \\t]*\\r?\\n[ \\t]*(\\p{Ll})",
            with: "$1$2",
            options: .regularExpression
        )
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
