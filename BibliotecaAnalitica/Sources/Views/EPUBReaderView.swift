import SwiftUI
import WebKit

/// Lector de EPUB: muestra un capítulo por vez y permite pasar de uno a otro.
/// El EPUB se descomprime en la caché de la app la primera vez que se abre.
struct EPUBReaderView: View {
    let store: LibraryStore
    let book: Book

    @State private var libro: EPUBLibro?
    @State private var indice = 0
    @State private var errorMensaje: String?

    var body: some View {
        Group {
            if let libro, !libro.capitulos.isEmpty {
                VStack(spacing: 0) {
                    EPUBWebView(url: libro.capitulos[indice], carpeta: carpetaExtraida)
                        .id(indice)
                    HStack {
                        Button {
                            indice -= 1
                        } label: {
                            Label("Anterior", systemImage: "chevron.left")
                        }
                        .disabled(indice == 0)

                        Spacer()
                        Text(tituloSeccion(libro))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()

                        Button {
                            indice += 1
                        } label: {
                            Label("Siguiente", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(indice >= libro.capitulos.count - 1)
                    }
                    .padding()
                }
            } else if let errorMensaje {
                ContentUnavailableView(
                    "No se pudo abrir el libro",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMensaje)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(book.title)
        .task { cargar() }
    }

    /// Título de la sección que se está leyendo. Sin números de página: un EPUB no está paginado.
    private func tituloSeccion(_ libro: EPUBLibro) -> String {
        let titulo = EPUBArchivo.titulo(de: libro.capitulos[indice])
        return titulo.isEmpty ? "Sección sin título" : titulo
    }

    /// Carpeta de caché donde se descomprime este EPUB (una por huella SHA-256).
    private var carpetaExtraida: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches
            .appendingPathComponent("EPUB", isDirectory: true)
            .appendingPathComponent(book.sha256, isDirectory: true)
    }

    private func cargar() {
        guard libro == nil else { return }
        do {
            let carpeta = carpetaExtraida
            if !FileManager.default.fileExists(atPath: carpeta.appendingPathComponent("META-INF").path) {
                try? FileManager.default.removeItem(at: carpeta)
                try EPUBArchivo.extraer(store.fileURL(for: book), en: carpeta)
            }
            libro = try EPUBArchivo.leer(carpeta: carpeta)
        } catch {
            errorMensaje = error.localizedDescription
        }
    }
}

/// Crea el WKWebView del lector. El JavaScript del libro queda desactivado.
private enum VistaEPUB {
    static func crear() -> WKWebView {
        let configuracion = WKWebViewConfiguration()
        configuracion.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuracion)
    }
}

#if os(macOS)
private struct EPUBWebView: NSViewRepresentable {
    let url: URL
    let carpeta: URL

    func makeNSView(context: Context) -> WKWebView {
        VistaEPUB.crear()
    }

    func updateNSView(_ vista: WKWebView, context: Context) {
        guard context.coordinator.cargada != url else { return }
        context.coordinator.cargada = url
        vista.loadFileURL(url, allowingReadAccessTo: carpeta)
    }

    func makeCoordinator() -> Coordinador {
        Coordinador()
    }
}
#else
private struct EPUBWebView: UIViewRepresentable {
    let url: URL
    let carpeta: URL

    func makeUIView(context: Context) -> WKWebView {
        VistaEPUB.crear()
    }

    func updateUIView(_ vista: WKWebView, context: Context) {
        guard context.coordinator.cargada != url else { return }
        context.coordinator.cargada = url
        vista.loadFileURL(url, allowingReadAccessTo: carpeta)
    }

    func makeCoordinator() -> Coordinador {
        Coordinador()
    }
}
#endif

extension EPUBWebView {
    /// Recuerda qué capítulo está cargado para no recargarlo en cada actualización de la vista.
    final class Coordinador {
        var cargada: URL?
    }
}
