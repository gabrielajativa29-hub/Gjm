import Foundation
import ZIPFoundation

/// Contenido de un EPUB ya descomprimido: metadatos, capítulos en orden de lectura y portada.
struct EPUBLibro {
    /// Título de los metadatos (puede estar vacío).
    let titulo: String
    /// Autores separados por «; ».
    let autores: String
    /// Capítulos en orden de lectura (ruta absoluta de cada XHTML).
    let capitulos: [URL]
    /// Imagen de portada, si el archivo la declara.
    let portada: URL?
}

enum EPUBError: LocalizedError {
    case sinContenedor
    case sinPaquete
    case sinCapitulos

    var errorDescription: String? {
        switch self {
        case .sinContenedor: return "No es un EPUB válido: falta META-INF/container.xml."
        case .sinPaquete: return "No es un EPUB válido: no se encuentra el archivo de paquete (.opf)."
        case .sinCapitulos: return "El EPUB no tiene capítulos de texto."
        }
    }
}

/// Lectura de EPUB: descompresión, estructura (container.xml y OPF) y texto de cada capítulo.
enum EPUBArchivo {
    /// Descomprime el archivo `.epub` en `carpeta` (que se crea si no existe).
    static func extraer(_ archivo: URL, en carpeta: URL) throws {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archivo, to: carpeta)
    }

    /// Lee la estructura de un EPUB ya descomprimido en `carpeta`.
    static func leer(carpeta: URL) throws -> EPUBLibro {
        guard let datosContenedor = try? Data(contentsOf: carpeta.appendingPathComponent("META-INF/container.xml")) else {
            throw EPUBError.sinContenedor
        }
        let contenedor = ContenedorParser()
        let parserContenedor = XMLParser(data: datosContenedor)
        parserContenedor.delegate = contenedor
        guard parserContenedor.parse(), let rutaPaquete = contenedor.rutaPaquete else {
            throw EPUBError.sinPaquete
        }

        let archivoPaquete = carpeta.appendingPathComponent(rutaPaquete)
        guard let datosPaquete = try? Data(contentsOf: archivoPaquete) else {
            throw EPUBError.sinPaquete
        }
        let paquete = PaqueteParser()
        let parserPaquete = XMLParser(data: datosPaquete)
        parserPaquete.delegate = paquete
        guard parserPaquete.parse() else { throw EPUBError.sinPaquete }

        // Las rutas del OPF son relativas a su propia carpeta.
        let carpetaPaquete = archivoPaquete.deletingLastPathComponent()
        func resolver(_ href: String) -> URL {
            URL(string: href, relativeTo: carpetaPaquete)?.absoluteURL
                ?? carpetaPaquete.appendingPathComponent(href)
        }

        let capitulos = paquete.lomo.compactMap { idref -> URL? in
            guard let item = paquete.manifiesto[idref], item.tipo.contains("html") else { return nil }
            return resolver(item.href)
        }
        guard !capitulos.isEmpty else { throw EPUBError.sinCapitulos }

        let idPortada = paquete.manifiesto.first { $0.value.propiedades.contains("cover-image") }?.key
            ?? paquete.idPortadaMeta
        let portada = idPortada
            .flatMap { paquete.manifiesto[$0] }
            .flatMap { item in item.tipo.hasPrefix("image/") ? resolver(item.href) : nil }

        return EPUBLibro(
            titulo: paquete.titulo,
            autores: paquete.autores.joined(separator: "; "),
            capitulos: capitulos,
            portada: portada
        )
    }

    /// Texto plano de un capítulo XHTML: sin etiquetas, sin scripts y con entidades decodificadas.
    static func texto(de capitulo: URL) -> String {
        guard let html = try? String(contentsOf: capitulo, encoding: .utf8) else { return "" }
        return textoPlano(html)
    }

    static func textoPlano(_ html: String) -> String {
        var texto = html.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        texto = texto.replacingOccurrences(
            of: "<br\\s*/?>|</(p|div|h[1-6]|li|tr)>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        texto = texto.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        texto = decodificarEntidades(texto)
        return texto
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func decodificarEntidades(_ texto: String) -> String {
        var resultado = texto
        let nombradas = ["&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">"]
        for (entidad, valor) in nombradas {
            resultado = resultado.replacingOccurrences(of: entidad, with: valor)
        }
        // Entidades numéricas: &#8220; y &#x201C;
        guard let patron = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") else { return resultado }
        let ns = resultado as NSString
        var salida = ""
        var desde = 0
        for coincidencia in patron.matches(in: resultado, range: NSRange(location: 0, length: ns.length)) {
            salida += ns.substring(with: NSRange(location: desde, length: coincidencia.range.location - desde))
            let codigo = ns.substring(with: coincidencia.range(at: 1))
            let valor = codigo.hasPrefix("x")
                ? UInt32(codigo.dropFirst(), radix: 16)
                : UInt32(codigo)
            if let valor, let escalar = Unicode.Scalar(valor) {
                salida.append(Character(escalar))
            }
            desde = coincidencia.range.location + coincidencia.range.length
        }
        salida += ns.substring(from: desde)
        // «&amp;» va al final: así «&amp;lt;» queda como «&lt;» y «&amp;#39;» como «&#39;», sin decodificar dos veces.
        return salida.replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Busca el archivo de paquete (`rootfile`) en META-INF/container.xml.
private final class ContenedorParser: NSObject, XMLParserDelegate {
    var rutaPaquete: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        if elementName.hasSuffix("rootfile"), rutaPaquete == nil {
            rutaPaquete = attributeDict["full-path"]
        }
    }
}

/// Lee el OPF: título, autores, manifiesto, orden de lectura (spine) y la marca de portada.
private final class PaqueteParser: NSObject, XMLParserDelegate {
    struct Item {
        let href: String
        let propiedades: String
        let tipo: String
    }

    var titulo = ""
    var autores: [String] = []
    var manifiesto: [String: Item] = [:]
    var lomo: [String] = []
    var idPortadaMeta: String?

    private var elementoTexto: String?
    private var textoActual = ""

    /// Nombre local de un elemento, sin prefijo (`dc:title` → `title`).
    private static func local(_ nombre: String) -> String {
        String(nombre.split(separator: ":").last ?? "")
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch Self.local(elementName) {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifiesto[id] = Item(
                    href: href,
                    propiedades: attributeDict["properties"] ?? "",
                    tipo: attributeDict["media-type"] ?? ""
                )
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                lomo.append(idref)
            }
        case "meta":
            if attributeDict["name"] == "cover", let contenido = attributeDict["content"] {
                idPortadaMeta = contenido
            }
        case let nombre where nombre == "title" || nombre == "creator":
            elementoTexto = nombre
            textoActual = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if elementoTexto != nil {
            textoActual += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let nombre = Self.local(elementName)
        guard nombre == elementoTexto else { return }
        let texto = textoActual.trimmingCharacters(in: .whitespacesAndNewlines)
        if nombre == "title", titulo.isEmpty {
            titulo = texto
        } else if nombre == "creator", !texto.isEmpty {
            autores.append(texto)
        }
        elementoTexto = nil
    }
}
