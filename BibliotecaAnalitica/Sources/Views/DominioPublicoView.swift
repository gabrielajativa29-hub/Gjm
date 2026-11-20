import SwiftUI

/// Busca libros de dominio público en Gutendex y los importa a la biblioteca.
/// Solo descarga lo que la fuente marca como dominio público y tiene PDF.
struct DominioPublicoView: View {
    let store: LibraryStore

    @State private var termino = "freud"
    @State private var resultados: [GutendexBook] = []
    @State private var buscando = false
    @State private var mensaje: String?

    var body: some View {
        List {
            Section {
                TextField("Autor o título", text: $termino)
                    .onSubmit { Task { await buscar() } }
                Button("Buscar") {
                    Task { await buscar() }
                }
                .disabled(buscando || termino.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Fuente: Gutendex (Project Gutenberg). Marcados como dominio público en EE. UU.; en otros países la regla puede ser distinta. Verifícalo antes de usarlos.")
            }

            if buscando {
                Section {
                    ProgressView("Buscando…")
                }
            }

            if !resultados.isEmpty {
                let descargables = resultados.filter(\.esDescargableAutomaticamente)
                Section {
                    Button("Cargar todos los PDF de dominio público (\(descargables.count))") {
                        Task { await cargarTodos(descargables) }
                    }
                    .disabled(descargables.isEmpty || buscando)
                }
            }

            Section("Resultados") {
                ForEach(resultados) { libro in
                    HStack(alignment: .top, spacing: 12) {
                        AsyncImage(url: libro.portadaURL) { imagen in
                            imagen
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Image(systemName: "book.closed")
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 60, height: 84)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(libro.title)
                                .font(.system(.headline, design: .serif))
                            if !libro.autorPrincipal.isEmpty {
                                Text(libro.autorPrincipal)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if libro.esDescargableAutomaticamente {
                                Button("Descargar PDF") {
                                    Task { await descargar(libro) }
                                }
                            } else {
                                Text("No se descarga: sin PDF o sin marca de dominio público.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Dominio público")
        .alert(
            "Dominio público",
            isPresented: Binding(
                get: { mensaje != nil },
                set: { if !$0 { mensaje = nil } }
            )
        ) {
            Button("OK") { mensaje = nil }
        } message: {
            Text(mensaje ?? "")
        }
    }

    private func buscar() async {
        buscando = true
        defer { buscando = false }
        do {
            resultados = try await GutendexClient.buscarDominioPublico(termino)
            if resultados.isEmpty {
                mensaje = "No se encontraron resultados en Gutendex para «\(termino)» con dominio público."
            }
        } catch {
            mensaje = error.localizedDescription
        }
    }

    private func descargar(_ libro: GutendexBook) async {
        buscando = true
        defer { buscando = false }
        do {
            let archivo = try await GutendexClient.descargarPDF(libro)
            mensaje = resumen(try store.importPDF(from: archivo), titulo: libro.title)
        } catch {
            mensaje = error.localizedDescription
        }
    }

    private func cargarTodos(_ libros: [GutendexBook]) async {
        buscando = true
        defer { buscando = false }
        var lineas: [String] = []
        for libro in libros {
            do {
                let archivo = try await GutendexClient.descargarPDF(libro)
                lineas.append(resumen(try store.importPDF(from: archivo), titulo: libro.title))
            } catch {
                lineas.append("«\(libro.title)»: \(error.localizedDescription)")
            }
        }
        mensaje = lineas.joined(separator: "\n")
    }

    private func resumen(_ resultado: ImportResult, titulo: String) -> String {
        switch resultado {
        case .added(let book):
            return "Añadido: «\(book.title)» (\(book.authorGroup.rawValue))."
        case .duplicateFile(let existing):
            return "Ya estaba en la biblioteca como «\(existing.title)»."
        case .duplicateRecord(let existing):
            return "Ya existe una ficha igual a «\(existing.title)»."
        }
    }
}
