import XCTest
@testable import BibliotecaAnalitica

final class TextNormalizerTests: XCTestCase {

    func testIgnoresAccentsAndCase() {
        XCTAssertTrue(TextNormalizer.matches("El Seminario de Lacan: La angustia", query: "ANGÚSTIA"))
        XCTAssertTrue(TextNormalizer.matches("El Seminario de Lacan: La angustia", query: "angustia"))
    }

    func testKeepsEnye() {
        // «año» y «ano» son palabras distintas: la ñ no se trata como n.
        XCTAssertFalse(TextNormalizer.matches("Año de Freud", query: "ano"))
        XCTAssertTrue(TextNormalizer.matches("Año de Freud", query: "AÑO"))
    }

    func testAllWordsMustAppearInAnyOrder() {
        XCTAssertTrue(TextNormalizer.matches("Freud, Obras completas", query: "obras freud"))
        XCTAssertFalse(TextNormalizer.matches("Freud, Obras completas", query: "obras lacan"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(TextNormalizer.matches("cualquier cosa", query: "   "))
    }
}
