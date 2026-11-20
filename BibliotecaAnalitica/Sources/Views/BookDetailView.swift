import SwiftUI

/// Ficha bibliográfica editable de un libro.
struct BookDetailView: View {
    let store: LibraryStore
    let onSaved: () -> Void

    @State private var draft: Book
    @State private var alertMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(store: LibraryStore, book: Book, onSaved: @escaping () -> Void) {
        self.store = store
        self.onSaved = onSaved
        _draft = State(initialValue: book)
    }

    var body: some View {
        Form {
            Section {
                PortadaView(url: store.portadaURL(for: draft))
                    .frame(maxWidth: .infinity, maxHeight: 220)
            }

            Section("Obra") {
                TextField("Título", text: $draft.title)
                TextField("Autor(es)", text: $draft.authors)
                Picker("Autor principal", selection: $draft.authorGroup) {
                    ForEach(AuthorGroup.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Tipo", selection: $draft.kind) {
                    ForEach(BookKind.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Obra mayor", text: $draft.majorWork)
                TextField("Volumen", text: $draft.volume)
                TextField("Número", text: $draft.number)
            }

            Section("Edición") {
                TextField("Año de la edición", value: $draft.editionYear, format: .number.grouping(.never))
                TextField("Año original", value: $draft.originalYear, format: .number.grouping(.never))
                TextField("Editor(es)", text: $draft.editors)
                TextField("Traductor(es)", text: $draft.translators)
                TextField("Editorial", text: $draft.publisher)
                TextField("Páginas", text: $draft.pages)
                TextField("DOI o URL", text: $draft.doiOrUrl)
                TextField("Idioma", text: $draft.language)
            }

            Section {
                TextField("Desfase de paginación", value: $draft.paginationOffset, format: .number.grouping(.never))
            } header: {
                Text("Paginación")
            } footer: {
                Text("Página del PDF menos página impresa. Ejemplo: si la página impresa 85 es la 90 del PDF, el desfase es 5.")
            }

            Section("Archivo") {
                LabeledContent("Formato", value: draft.format.rawValue.uppercased())
                LabeledContent("Huella SHA-256", value: String(draft.sha256.prefix(16)) + "…")
            }
        }
        .navigationTitle(draft.title)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
            }
        }
        .alert(
            "No se pudo guardar",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func save() {
        do {
            if let conflict = try store.save(draft) {
                alertMessage = "Ya existe una ficha con el mismo título, autor, año y traductor: «\(conflict.title)»."
            } else {
                onSaved()
                dismiss()
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
