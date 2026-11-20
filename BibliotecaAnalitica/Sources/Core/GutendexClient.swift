import Foundation

/// Persona (autor o traductor) tal como la devuelve Gutendex.
struct GutendexPerson: Decodable {
    let name: String
}

/// Libro de Project Gutenberg según la API de Gutendex (https://gutendex.com).
/// Campos usados: id, title, authors, copyright, formats.
struct GutendexBook: Decodable, Identifiable {
    let id: Int
    let title: String
    let authors: [GutendexPerson]
    /// `false` = dominio público en EE. UU.; `true` = con derechos; `nil` = sin información.
    let copyright: Bool?
    /// Tipo MIME → URL de descarga.
    let formats: [String: String]

    var autorPrincipal: String {
        authors.first?.name ?? ""
    }

    /// URL del PDF, si la fuente lo ofrece.
    var pdfURL: URL? {
        formats["application/pdf"].flatMap { URL(string: $0) }
    }

    /// URL de la portada (imagen JPEG), si la fuente la ofrece.
    var portadaURL: URL? {
        formats["image/jpeg"].flatMap { URL(string: $0) }
    }

    /// Solo se descarga si la fuente lo marca como dominio público (EE. UU.) y hay PDF.
    var esDescargableAutomaticamente: Bool {
        copyright == false && pdfURL != nil
    }
}

struct GutendexRespuesta: Decodable {
    let count: Int
    let results: [GutendexBook]
}

enum GutendexError: LocalizedError {
    case respuestaInvalida
    case sinPDF
    case noEsDominioPublico

    var errorDescription: String? {
        switch self {
        case .respuestaInvalida: return "Gutendex no respondió correctamente."
        case .sinPDF: return "Este libro no tiene PDF disponible en la fuente."
        case .noEsDominioPublico: return "La fuente no marca este libro como dominio público. No se descarga."
        }
    }
}

enum GutendexClient {
    /// Busca libros marcados como dominio público en EE. UU. que coincidan con `termino`.
    static func buscarDominioPublico(_ termino: String) async throws -> [GutendexBook] {
        var componentes = URLComponents(string: "https://gutendex.com/books/")!
        componentes.queryItems = [
            URLQueryItem(name: "search", value: termino),
            URLQueryItem(name: "copyright", value: "false")
        ]
        guard let url = componentes.url else { throw GutendexError.respuestaInvalida }

        var solicitud = URLRequest(url: url)
        solicitud.setValue("BibliotecaAnalitica/1.0", forHTTPHeaderField: "User-Agent")

        let (datos, respuesta) = try await URLSession.shared.data(for: solicitud)
        guard (respuesta as? HTTPURLResponse)?.statusCode == 200 else {
            throw GutendexError.respuestaInvalida
        }
        return try JSONDecoder().decode(GutendexRespuesta.self, from: datos).results
    }

    /// Descarga el PDF de un libro de dominio público a una carpeta temporal
    /// y devuelve la ruta del archivo, lista para importarla a la biblioteca.
    static func descargarPDF(_ libro: GutendexBook) async throws -> URL {
        guard libro.copyright == false else { throw GutendexError.noEsDominioPublico }
        guard let origen = libro.pdfURL else { throw GutendexError.sinPDF }

        let (temporal, _) = try await URLSession.shared.download(from: origen)

        let nombre = libro.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nombre).pdf")
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.moveItem(at: temporal, to: destino)
        return destino
    }
}
//
//  GutendexClient.swift
//  BibliotecaAnalitica
//
//  Created by GJM7 on 18/11/26.
//

