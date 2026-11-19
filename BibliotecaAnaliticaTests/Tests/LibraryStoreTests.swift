import PDFKit
import XCTest
@testable import BibliotecaAnalitica

final class LibraryStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() throws -> LibraryStore {
        try LibraryStore(
            folder: tempDir.appendingPathComponent("Libros", isDirectory: true),
            databaseURL: tempDir.appendingPathComponent("test.sqlite")
        )
    }

    /// Crea un PDF de prueba con `pages` páginas en blanco, dentro de `subfolder`.
    private func makePDF(pages: Int, subfolder: String, named name: String) throws -> URL {
        let document = PDFDocument()
        for index in 0..<pages {
            document.insert(PDFPage(), at: index)
        }
        let directory = tempDir.appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let data = try XCTUnwrap(document.dataRepresentation())
        try data.write(to: url)
        return url
    }

    func testSameFileTwiceIsRejectedByHash() throws {
        let store = try makeStore()
        let url = try makePDF(pages: 2, subfolder: "a", named: "Libro de prueba.pdf")

        guard case .added = try store.importPDF(from: url) else {
            return XCTFail("La primera importación debería añadirse.")
        }
        guard case .duplicateFile = try store.importPDF(from: url) else {
            return XCTFail("La segunda importación del mismo archivo debería rechazarse.")
        }
    }

    func testSameRecordWithDifferentFileIsRejected() throws {
        let store = try makeStore()
        // Mismo nombre → mismo título sin metadatos; distinto contenido → distinta huella.
        let first = try makePDF(pages: 2, subfolder: "a", named: "Libro de prueba.pdf")
        let second = try makePDF(pages: 3, subfolder: "b", named: "Libro de prueba.pdf")

        guard case .added = try store.importPDF(from: first) else {
            return XCTFail("La primera importación debería añadirse.")
        }
        guard case .duplicateRecord(let existing) = try store.importPDF(from: second) else {
            return XCTFail("Una ficha idéntica debería rechazarse por duplicado de ficha.")
        }
        XCTAssertEqual(existing.title, "Libro de prueba")
    }

    func testSearchFindsBookWithoutAccentsOrCase() throws {
        let store = try makeStore()
        let url = try makePDF(pages: 1, subfolder: "a", named: "Seminario 10 - La angustia.pdf")
        _ = try store.importPDF(from: url)

        XCTAssertEqual(try store.books(matching: "angustia").count, 1)
        XCTAssertEqual(try store.books(matching: "ANGUSTIA").count, 1)
        XCTAssertEqual(try store.books(matching: "seminario lacan").count, 0)
    }
}
