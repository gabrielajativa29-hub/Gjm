import XCTest
@testable import BibliotecaAnalitica

final class EPUBArchivoTests: XCTestCase {

    func testRemovesTagsAndScripts() {
        let html = "<html><head><script>var x = 1;</script></head><body><p>Hola <em>mundo</em></p></body></html>"
        XCTAssertEqual(EPUBArchivo.textoPlano(html), "Hola mundo")
    }

    func testParagraphsBecomeLines() {
        let html = "<p>Primera</p><p>Segunda</p>"
        XCTAssertEqual(EPUBArchivo.textoPlano(html), "Primera\nSegunda")
    }

    func testDecodesNamedAndNumericEntities() {
        XCTAssertEqual(EPUBArchivo.textoPlano("Freud &amp; Lacan&#8212;&#x201C;citas&#x201D;"), "Freud & Lacan—“citas”")
    }
}
