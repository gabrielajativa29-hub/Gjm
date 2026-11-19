import Foundation
import GRDB

/// Autor principal, para clasificar la biblioteca.
enum AuthorGroup: String, Codable, CaseIterable, Identifiable {
    case freud = "Freud"
    case lacan = "Lacan"
    case miller = "Miller"
    case otros = "Otros"

    var id: String { rawValue }
}

enum BookKind: String, Codable, CaseIterable, Identifiable {
    case libro = "Libro"
    case textoEnObraMayor = "Texto dentro de obra mayor"
    case articulo = "Artículo"

    var id: String { rawValue }
}

enum FileFormat: String, Codable, CaseIterable {
    case pdf, epub, txt, md
}

/// Libro de la biblioteca con su ficha bibliográfica editable.
struct Book: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "book"

    var id: Int64?
    /// Huella SHA-256 del archivo: base del control de duplicados por contenido.
    var sha256: String
    /// Nombre del archivo dentro de la carpeta de la biblioteca.
    var fileName: String
    var format: FileFormat

    // Ficha bibliográfica
    var title: String
    /// Autor(es), separados por «; ».
    var authors: String = ""
    var authorGroup: AuthorGroup = .otros
    /// Clave de botón propio (carpeta o autor). Vacía si no aplica.
    var etiqueta: String = ""
    var editionYear: Int?
    var originalYear: Int?
    var editors: String = ""
    var translators: String = ""
    var publisher: String = ""
    var kind: BookKind = .libro
    var majorWork: String = ""
    var volume: String = ""
    var number: String = ""
    var pages: String = ""
    var doiOrUrl: String = ""
    var language: String = "es"
    /// Página del PDF menos página impresa. Se usa para calcular la página citada (fase 3).
    var paginationOffset: Int = 0

    var importedAt: Date = .now

    mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    /// Clave de duplicados: título + autor(es) + año de edición + traductor(es),
    /// comparada sin tildes ni mayúsculas.
    var duplicateKey: String {
        [
            TextNormalizer.key(title),
            TextNormalizer.key(authors),
            editionYear.map { String($0) } ?? "",
            TextNormalizer.key(translators)
        ].joined(separator: "|")
    }

    /// Texto sobre el que busca el buscador de la biblioteca.
    var searchableText: String {
        [
            title, authors, editors, translators, publisher, majorWork,
            editionYear.map { String($0) } ?? "",
            originalYear.map { String($0) } ?? ""
        ].joined(separator: " ")
    }
}
