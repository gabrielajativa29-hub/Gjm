import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Lista de libros. Puede mostrar toda la biblioteca o solo los de un autor.
/// No tiene NavigationStack propio: se apila desde AutoresView.
struct LibraryView: View {
    let store: LibraryStore
    var group: AuthorGroup? = nil
    var etiqueta: String? = nil
    var title: String = "Biblioteca"

    @State private var query = ""
    @State private var books: [Book] = []
    @State private var isImporting = false
    @State private var alertMessage: String?
    @State private var bookToDelete: Book?
    @State private var isImportingFolder = false

    /// Formatos que se pueden importar.
    private static let extensionesImportables = ["pdf", "epub"]
    private static var tiposImportables: [UTType] {
        [UTType.pdf] + (UTType(filenameExtension: "epub").map { [$0] } ?? [])
    }

    var body: some View {
        List {
            ForEach(Array(books.enumerated()), id: \.element.id) { indice, book in
            NavigationLink(value: book) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(indice + 1).")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 32, alignment: .trailing)
                    BookRow(book: book, portada: store.portadaURL(for: book))
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    bookToDelete = book
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    bookToDelete = book
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
            }
        }
        .overlay {
            if books.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Sin libros",
                        systemImage: "books.vertical",
                        description: Text(etiqueta == "cuadernos-icdeba"
                            ? "Usa el botón de carpeta (arriba a la derecha) y elige «Cuadernos ICdeBA» dentro de Documentos."
                            : "Añade un PDF o un EPUB con el botón +, o arrástralo a la ventana.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Título, autor, año, traductor")
        .onChange(of: query) { _, _ in reload() }
        .toolbar {
            Button {
                isImporting = true
            } label: {
                Label("Añadir libro", systemImage: "plus")
            }
            Button {
                isImportingFolder = true
            } label: {
                Label("Importar carpeta", systemImage: "folder.badge.plus")
            }
        }
        .fileImporter(
            isPresented: $isImportingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let carpeta):
                importFolder(carpeta)
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: Self.tiposImportables,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                alertMessage = error.localizedDescription
            }
        }
        // Arrastrar y soltar (Mac): acepta PDF sueltos o carpetas completas.
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                var esCarpeta: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &esCarpeta), esCarpeta.boolValue {
                    importFolder(url)
                } else if Self.extensionesImportables.contains(url.pathExtension.lowercased()) {
                    importFiles([url])
                }
            }
            return true
        }
        .alert(
            "Biblioteca",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "¿Borrar este libro?",
            isPresented: Binding(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                deleteBook()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará de la biblioteca y su archivo PDF. No se puede deshacer.")
        }
        .onAppear { reload() }
    }

    private func deleteBook() {
        guard let book = bookToDelete else { return }
        bookToDelete = nil
        do {
            try store.delete(book)
            reload()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            books = try store.books(matching: query, group: group, etiqueta: etiqueta)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Importa todos los PDF de la carpeta elegida y sus subcarpetas.
    private func importFolder(_ carpeta: URL) {
        let accedido = carpeta.startAccessingSecurityScopedResource()
        defer {
            if accedido { carpeta.stopAccessingSecurityScopedResource() }
        }
        guard let enumerador = FileManager.default.enumerator(
            at: carpeta,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            alertMessage = "No se pudo leer la carpeta."
            return
        }
        var pdfs: [URL] = []
        for case let url as URL in enumerador where Self.extensionesImportables.contains(url.pathExtension.lowercased()) {
            pdfs.append(url)
        }
        if pdfs.isEmpty {
            alertMessage = "No hay archivos PDF ni EPUB en esa carpeta."
            return
        }
        importFiles(
            pdfs,
            grupo: LibraryStore.grupoDesdeTexto(carpeta.lastPathComponent),
            etiqueta: LibraryStore.etiquetaDesde(carpeta.lastPathComponent)
        )
    }

    private func importFiles(_ urls: [URL], grupo: AuthorGroup? = nil, etiqueta: String? = nil) {
        var messages: [String] = []
        for url in urls {
            do {
                let resultado = url.pathExtension.lowercased() == "epub"
                    ? try store.importEPUB(from: url, grupo: grupo, etiqueta: etiqueta)
                    : try store.importPDF(from: url, grupo: grupo, etiqueta: etiqueta)
                switch resultado {
                case .added(let book):
                    messages.append("Añadido: «\(book.title)» (\(book.authorGroup.rawValue)).")
                case .duplicateFile(let existing):
                    messages.append("Rechazado: ese archivo ya está en la biblioteca como «\(existing.title)».")
                case .duplicateRecord(let existing):
                    messages.append("Rechazado: ya existe una ficha con el mismo título, autor, año y traductor («\(existing.title)»).")
                }
            } catch {
                messages.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        reload()
        if !messages.isEmpty {
            alertMessage = messages.joined(separator: "\n")
        }
    }
}

struct BookRow: View {
    let book: Book
    var portada: URL? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PortadaView(url: portada)
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(.headline, design: .serif))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        [book.authors, book.editionYear.map { String($0) } ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Portada del libro. Si no hay imagen, muestra un icono de libro.
struct PortadaView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let imagen = Self.cargar(url) {
                imagen
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "book.closed")
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .foregroundStyle(.secondary)
            }
        }
        .background(Color.secondary.opacity(0.1))
    }

    private static func cargar(_ url: URL) -> Image? {
        #if os(macOS)
        guard let imagen = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: imagen)
        #else
        guard let imagen = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: imagen)
        #endif
    }
}
