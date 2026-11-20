import Foundation
import GRDB
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ImportResult {
    case added(Book)
    /// Mismo contenido (misma huella SHA-256) que un libro ya existente.
    case duplicateFile(existing: Book)
    /// Misma ficha (título + autor + año + traductor) que un libro ya existente.
    case duplicateRecord(existing: Book)
}

enum LibraryError: LocalizedError {
    case notAPDF

    var errorDescription: String? {
        switch self {
        case .notAPDF:
            return "El archivo no es un PDF válido."
        }
    }
}

/// Resultado de buscar una frase: una página de un libro.
struct ResultadoCita: Identifiable, Hashable {
    let id = UUID()
    let bookId: Int64
    let titulo: String
    let formato: FileFormat
    /// Número de página del PDF (empieza en 1). Solo aplica a PDF.
    let numeroPDF: Int
    let paginationOffset: Int
    /// Título de la sección donde está el texto (EPUB). Vacío si no tiene título.
    let seccion: String
    /// Texto completo de la página o de la sección.
    let texto: String

    /// Solo los PDF tienen paginación. EPUB y Word se citan por sección, sin número de página.
    var esPaginado: Bool {
        formato == .pdf
    }

    /// Página impresa = página del PDF menos el desfase de la ficha.
    var paginaImpresa: Int {
        numeroPDF - paginationOffset
    }

    /// Texto que indica dónde está la cita.
    var ubicacion: String {
        if esPaginado {
            return "Página impresa \(paginaImpresa) · página del PDF \(numeroPDF)"
        }
        return seccion.isEmpty ? "Sección sin título" : seccion
    }
}

/// Acceso a la base de datos (SQLite vía GRDB) y a la carpeta de archivos.
final class LibraryStore {
    let folder: URL
    private let dbQueue: DatabaseQueue

    init(folder: URL, databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        self.dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(dbQueue)
        // Indexa el texto de los libros que aún no tienen páginas guardadas.
        try? indexarLibrosPendientes()
        asegurarPortadas()
    }

    /// Carpeta por defecto en Application Support. La fase 7 la pasará a iCloud Drive.
    static func makeDefault() throws -> LibraryStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appendingPathComponent("BibliotecaAnalitica", isDirectory: true)
        return try LibraryStore(
            folder: root.appendingPathComponent("Libros", isDirectory: true),
            databaseURL: root.appendingPathComponent("biblioteca.sqlite")
        )
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-book") { db in
            try db.create(table: "book") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sha256", .text).notNull().unique()
                t.column("fileName", .text).notNull()
                t.column("format", .text).notNull()
                t.column("title", .text).notNull()
                t.column("authors", .text).notNull()
                t.column("authorGroup", .text).notNull()
                t.column("editionYear", .integer)
                t.column("originalYear", .integer)
                t.column("editors", .text).notNull()
                t.column("translators", .text).notNull()
                t.column("publisher", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("majorWork", .text).notNull()
                t.column("volume", .text).notNull()
                t.column("number", .text).notNull()
                t.column("pages", .text).notNull()
                t.column("doiOrUrl", .text).notNull()
                t.column("language", .text).notNull()
                t.column("paginationOffset", .integer).notNull()
                t.column("importedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2-etiqueta") { db in
            try db.alter(table: "book") { t in
                t.add(column: "etiqueta", .text).notNull().defaults(to: "")
            }
        }
        migrator.registerMigration("v3-paginas") { db in
            try db.create(table: "pagina") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bookId", .integer).notNull()
                t.column("numero", .integer).notNull()
                t.column("texto", .text).notNull()
                t.column("textoNorm", .text).notNull()
            }
            try db.create(index: "pagina_por_libro", on: "pagina", columns: ["bookId"])
        }
        migrator.registerMigration("v4-ocr-y-guiones") { db in
            try db.alter(table: "book") { t in
                t.add(column: "paginasTotales", .integer).notNull().defaults(to: 0)
                t.add(column: "ocrEstado", .text).notNull().defaults(to: OCRStatus.noAplica.rawValue)
            }
            // Libros sin ninguna página con texto: necesitan OCR.
            try db.execute(sql: """
                UPDATE book SET ocrEstado = ?
                WHERE id NOT IN (SELECT DISTINCT bookId FROM pagina)
                """, arguments: [OCRStatus.pendiente.rawValue])
            // Reindexa las páginas existentes con la unión de palabras partidas por guion.
            let paginas = try Row.fetchAll(db, sql: "SELECT id, texto FROM pagina")
            for pagina in paginas {
                let id: Int64 = pagina["id"]
                let texto: String = pagina["texto"]
                try db.execute(
                    sql: "UPDATE pagina SET textoNorm = ? WHERE id = ?",
                    arguments: [TextNormalizer.indexKey(texto), id]
                )
            }
        }
        migrator.registerMigration("v5-ubicacion") { db in
            // Nombre de la sección (EPUB). En PDF queda vacío: se cita por número de página.
            try db.alter(table: "pagina") { t in
                t.add(column: "ubicacion", .text).notNull().defaults(to: "")
            }
        }
        return migrator
    }

    // MARK: - Importación

    /// Importa un PDF. Rechaza duplicados por contenido y por ficha antes de copiar nada.
    func importPDF(from source: URL, grupo: AuthorGroup? = nil, etiqueta: String? = nil) throws -> ImportResult {
        let didStartAccess = source.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { source.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: source)
        guard let pdf = PDFDocument(data: data) else {
            throw LibraryError.notAPDF
        }

        let hash = FileHasher.sha256Hex(of: data)
        let fallbackTitle = source.deletingPathExtension().lastPathComponent
        let metadataTitle = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? ""
        let metadataAuthor = (pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""

        let authors = metadataAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = metadataTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : metadataTitle
        // Etiqueta final: la de la carpeta o, si no hay, la del autor.
        let etiquetaFinal = etiqueta ?? Self.etiquetaDesdeAutor(authors + " " + title)
        let draft = Book(
            sha256: hash,
            fileName: "\(hash).pdf",
            format: .pdf,
            title: title,
            authors: authors,
            authorGroup: grupo ?? Self.inferGroup(fromAuthors: authors, title: title),
            etiqueta: etiquetaFinal ?? ""
        )

        return try importarNuevo(data: data, draft: draft, grupo: grupo, etiqueta: etiquetaFinal) { db, book in
            guard let libroId = book.id else { return }
            let conTexto = try Self.indexarPaginas(de: pdf, libroId: libroId, en: db)
            try Self.registrarEstadoOCR(libroId: libroId, paginasTotales: pdf.pageCount, paginasConTexto: conTexto, en: db)
            book.paginasTotales = pdf.pageCount
            book.ocrEstado = Self.estadoOCR(paginasTotales: pdf.pageCount, paginasConTexto: conTexto)
            try? Self.guardarPortada(de: pdf, en: portadaURL(for: book))
        }
    }

    /// Importa un EPUB: lo descomprime en una carpeta temporal, lee su estructura, guarda el texto de
    /// cada capítulo (como sección, sin número de página) y su portada.
    func importEPUB(from source: URL, grupo: AuthorGroup? = nil, etiqueta: String? = nil) throws -> ImportResult {
        let didStartAccess = source.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { source.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: source)
        let hash = FileHasher.sha256Hex(of: data)

        let temporal = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporal) }

        let archivo = temporal.appendingPathComponent("libro.epub")
        try data.write(to: archivo)
        let extraido = temporal.appendingPathComponent("contenido", isDirectory: true)
        try EPUBArchivo.extraer(archivo, en: extraido)
        let libro = try EPUBArchivo.leer(carpeta: extraido)

        let fallbackTitle = source.deletingPathExtension().lastPathComponent
        let title = libro.titulo.isEmpty ? fallbackTitle : libro.titulo
        let authors = libro.autores
        let etiquetaFinal = etiqueta ?? Self.etiquetaDesdeAutor(authors + " " + title)
        let draft = Book(
            sha256: hash,
            fileName: "\(hash).epub",
            format: .epub,
            title: title,
            authors: authors,
            authorGroup: grupo ?? Self.inferGroup(fromAuthors: authors, title: title),
            etiqueta: etiquetaFinal ?? ""
        )

        // El texto y la portada se leen antes de entrar en la transacción de la base de datos.
        let textos = libro.capitulos.map { EPUBArchivo.texto(de: $0) }
        let titulos = libro.capitulos.map { EPUBArchivo.titulo(de: $0) }
        let portadaDatos = libro.portada.flatMap { try? Data(contentsOf: $0) }

        return try importarNuevo(data: data, draft: draft, grupo: grupo, etiqueta: etiquetaFinal) { db, book in
            guard let libroId = book.id else { return }
            var conTexto = 0
            for (indice, texto) in textos.enumerated() {
                let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !limpio.isEmpty else { continue }
                conTexto += 1
                // Sin número de página (el EPUB no tiene paginación): se guarda el título de la sección.
                try db.execute(
                    sql: "INSERT INTO pagina (bookId, numero, texto, textoNorm, ubicacion) VALUES (?, 0, ?, ?, ?)",
                    arguments: [libroId, limpio, TextNormalizer.indexKey(limpio), titulos[indice]]
                )
            }
            // Un EPUB no tiene páginas escaneadas: nunca necesita OCR.
            book.paginasTotales = textos.count
            book.ocrEstado = .noAplica
            try book.update(db)
            if let portadaDatos {
                try FileManager.default.createDirectory(at: folder.appendingPathComponent("Portadas", isDirectory: true), withIntermediateDirectories: true)
                try portadaDatos.write(to: portadaURL(for: book), options: .atomic)
            }
        }
    }

    /// Escribe un libro nuevo (archivo y ficha) tras comprobar duplicados por contenido y por ficha.
    /// `indexar` recibe la ficha ya insertada (con su `id`) para guardar sus páginas y su portada.
    private func importarNuevo(
        data: Data,
        draft: Book,
        grupo: AuthorGroup?,
        etiqueta etiquetaFinal: String?,
        indexar: (Database, inout Book) throws -> Void
    ) throws -> ImportResult {
        try dbQueue.write { db -> ImportResult in
            if var existing = try Book.filter(Column("sha256") == draft.sha256).fetchOne(db) {
                // Si el libro ya estaba pero ahora llega con un grupo distinto (por ejemplo, desde una carpeta «freud»), se actualiza.
                var cambio = false
                if let grupo, existing.authorGroup != grupo {
                    existing.authorGroup = grupo
                    cambio = true
                }
                if let etiquetaFinal, existing.etiqueta != etiquetaFinal {
                    existing.etiqueta = etiquetaFinal
                    cambio = true
                }
                if cambio { try existing.update(db) }
                return .duplicateFile(existing: existing)
            }

            let key = draft.duplicateKey
            if var existing = try Book.fetchAll(db).first(where: { $0.duplicateKey == key }) {
                // Misma ficha con otro archivo: si llega con un grupo distinto, también se actualiza.
                var cambio = false
                if let grupo, existing.authorGroup != grupo {
                    existing.authorGroup = grupo
                    cambio = true
                }
                if let etiquetaFinal, existing.etiqueta != etiquetaFinal {
                    existing.etiqueta = etiquetaFinal
                    cambio = true
                }
                if cambio { try existing.update(db) }
                return .duplicateRecord(existing: existing)
            }

            var book = draft
            let destination = folder.appendingPathComponent(book.fileName)
            try data.write(to: destination, options: .atomic)

            do {
                try book.insert(db)
                try indexar(db, &book)
            } catch {
                // Si la inserción falla, no dejar un archivo huérfano.
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            return .added(book)
        }
    }

    // MARK: - Texto de las páginas y búsqueda de citas

    /// Guarda el texto de cada página del PDF para poder buscar citas.
    /// Devuelve cuántas páginas tenían texto.
    @discardableResult
    private static func indexarPaginas(de pdf: PDFDocument, libroId: Int64, en db: Database) throws -> Int {
        var conTexto = 0
        for indice in 0..<pdf.pageCount {
            let texto = (pdf.page(at: indice)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { continue }
            conTexto += 1
            try db.execute(
                sql: "INSERT INTO pagina (bookId, numero, texto, textoNorm) VALUES (?, ?, ?, ?)",
                arguments: [libroId, indice + 1, texto, TextNormalizer.indexKey(texto)]
            )
        }
        return conTexto
    }

    /// Un libro necesita OCR si más de la mitad de sus páginas no tiene texto.
    static func estadoOCR(paginasTotales: Int, paginasConTexto: Int) -> OCRStatus {
        paginasTotales > 0 && paginasConTexto * 2 < paginasTotales ? .pendiente : .noAplica
    }

    /// Guarda en la ficha el número de páginas y el estado de OCR.
    private static func registrarEstadoOCR(libroId: Int64, paginasTotales: Int, paginasConTexto: Int, en db: Database) throws {
        try db.execute(
            sql: "UPDATE book SET paginasTotales = ?, ocrEstado = ? WHERE id = ?",
            arguments: [paginasTotales, estadoOCR(paginasTotales: paginasTotales, paginasConTexto: paginasConTexto).rawValue, libroId]
        )
    }

    /// Indexa los libros que todavía no tienen páginas guardadas (por ejemplo, los importados antes de esta versión).
    func indexarLibrosPendientes() throws {
        let pendientes = try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, fileName FROM book
                WHERE id NOT IN (SELECT DISTINCT bookId FROM pagina)
                """)
        }
        for fila in pendientes {
            let libroId: Int64 = fila["id"]
            let nombre: String = fila["fileName"]
            guard let pdf = PDFDocument(url: folder.appendingPathComponent(nombre)) else { continue }
            try dbQueue.write { db in
                let conTexto = try Self.indexarPaginas(de: pdf, libroId: libroId, en: db)
                try Self.registrarEstadoOCR(libroId: libroId, paginasTotales: pdf.pageCount, paginasConTexto: conTexto, en: db)
            }
        }
    }

    /// Busca una frase (o palabras) en el texto de todas las páginas, sin distinguir tildes ni mayúsculas.
    func buscarCitas(_ consulta: String, limite: Int = 200) throws -> [ResultadoCita] {
        let termino = TextNormalizer.key(consulta)
        guard !termino.isEmpty else { return [] }
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.bookId, p.numero, p.texto, p.ubicacion, b.title, b.format, b.paginationOffset
                FROM pagina p
                JOIN book b ON b.id = p.bookId
                WHERE p.textoNorm LIKE ?
                ORDER BY b.title, p.numero
                LIMIT ?
                """, arguments: ["%\(termino)%", limite]).map { fila -> ResultadoCita in
                let formato: String = fila["format"]
                return ResultadoCita(
                    bookId: fila["bookId"],
                    titulo: fila["title"],
                    formato: FileFormat(rawValue: formato) ?? .pdf,
                    numeroPDF: fila["numero"],
                    paginationOffset: fila["paginationOffset"],
                    seccion: fila["ubicacion"],
                    texto: fila["texto"]
                )
            }
        }
    }

    // MARK: - Consulta y edición

    /// Libros cuya ficha contiene todas las palabras de `query` (sin tildes ni mayúsculas).
    /// Si se indica `group`, solo los de ese autor principal.
    func books(matching query: String, group: AuthorGroup? = nil, etiqueta: String? = nil) throws -> [Book] {
        let all = try dbQueue.read { db in
            try Book.order(Column("title")).fetchAll(db)
        }
        return all
            .filter { book in
                (group == nil || book.authorGroup == group)
                    && (etiqueta == nil || book.etiqueta == etiqueta)
                    && TextNormalizer.matches(book.searchableText, query: query)
            }
            // Orden alfabético en español (ignora mayúsculas, respeta tildes y números).
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Sugiere el autor principal a partir del primer autor de los metadatos del PDF.
    /// Si no lo reconoce, devuelve «Otros». Siempre se puede corregir en la ficha.
    static func inferGroup(fromAuthors authors: String, title: String) -> AuthorGroup {
        let primerAutor = authors.components(separatedBy: ";").first ?? ""
        return grupoDesdeTexto(primerAutor) ?? grupoDesdeTexto(title) ?? .otros
    }

    /// Botón propio según el nombre de la carpeta (Psiquiatría clásica, Psicopatología).
    static func etiquetaDesde(_ carpeta: String) -> String? {
        let normalizado = TextNormalizer.key(carpeta)
        if normalizado.contains("psiquiatria clasica") { return "psiquiatria-clasica" }
        if normalizado.contains("psicopatologia") { return "psicopatologia" }
        return nil
    }

    /// Botón propio según el autor (José María Álvarez).
    static func etiquetaDesdeAutor(_ texto: String) -> String? {
        TextNormalizer.key(texto).contains("jose maria alvarez") ? "jose-maria-alvarez" : nil
    }

    /// Busca Freud, Lacan o Miller dentro de un texto (autor, título o nombre de carpeta).
    static func grupoDesdeTexto(_ texto: String) -> AuthorGroup? {
        let normalizado = TextNormalizer.key(texto)
        if normalizado.contains("freud") { return .freud }
        if normalizado.contains("lacan") { return .lacan }
        if normalizado.contains("miller") { return .miller }
        return nil
    }

    func fileURL(for book: Book) -> URL {
        folder.appendingPathComponent(book.fileName)
    }

    // MARK: - Portadas

    /// Imagen JPEG de la portada. Se guarda en una subcarpeta con el nombre de la huella del libro.
    /// Puede no existir todavía (por ejemplo, si el libro es un EPUB o si la generación falló).
    func portadaURL(for book: Book) -> URL {
        folder
            .appendingPathComponent("Portadas", isDirectory: true)
            .appendingPathComponent("\(book.sha256).jpg")
    }

    /// Genera la portada de un PDF a partir de su primera página, de 300 px de ancho.
    static func guardarPortada(de pdf: PDFDocument, en destino: URL) throws {
        guard let primera = pdf.page(at: 0) else { return }
        let caja = primera.bounds(for: .mediaBox)
        guard caja.width > 0 else { return }
        let ancho: CGFloat = 300
        let alto = ancho * caja.height / caja.width
        let imagen = primera.thumbnail(of: CGSize(width: ancho, height: alto), for: .mediaBox)
        #if os(macOS)
        guard let tiff = imagen.tiffRepresentation,
              let representacion = NSBitmapImageRep(data: tiff),
              let jpeg = representacion.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return }
        #else
        guard let jpeg = imagen.jpegData(compressionQuality: 0.8) else { return }
        #endif
        try FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: destino, options: .atomic)
    }

    /// Genera las portadas que falten en los PDF (libros importados antes de esta versión).
    func asegurarPortadas() {
        guard let libros = try? dbQueue.read({ db in
            try Book.filter(Column("format") == FileFormat.pdf.rawValue).fetchAll(db)
        }) else { return }
        for libro in libros {
            let destino = portadaURL(for: libro)
            guard !FileManager.default.fileExists(atPath: destino.path),
                  let pdf = PDFDocument(url: fileURL(for: libro)) else { continue }
            try? Self.guardarPortada(de: pdf, en: destino)
        }
    }

    /// Borra el libro de la base de datos y, después, su archivo PDF y su portada.
    func delete(_ book: Book) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM pagina WHERE bookId = ?", arguments: [book.id])
            _ = try book.delete(db)
        }
        try? FileManager.default.removeItem(at: fileURL(for: book))
        try? FileManager.default.removeItem(at: portadaURL(for: book))
    }

    /// Guarda cambios de una ficha existente. Devuelve el libro en conflicto si la ficha
    /// duplica a otra (en ese caso no guarda nada); devuelve `nil` si guardó correctamente.
    func save(_ book: Book) throws -> Book? {
        try dbQueue.write { db -> Book? in
            let key = book.duplicateKey
            if let conflict = try Book.fetchAll(db).first(where: { $0.id != book.id && $0.duplicateKey == key }) {
                return conflict
            }
            let copy = book
            try copy.update(db)
            return nil
        }
    }
}
