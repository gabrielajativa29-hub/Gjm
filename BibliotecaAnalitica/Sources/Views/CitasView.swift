import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Busca una frase en el texto de los libros y muestra cada página donde aparece.
struct CitasView: View {
    let store: LibraryStore

    @State private var consulta = ""
    @State private var resultados: [ResultadoCita] = []
    @State private var mensaje: String?

    var body: some View {
        List {
            if resultados.isEmpty, !consulta.isEmpty {
                Text("No se encontraron resultados en la biblioteca para «\(consulta)».")
                    .foregroundStyle(.secondary)
            }

            ForEach(resultados) { resultado in
                NavigationLink(value: resultado) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resultado.titulo)
                            .font(.system(.headline, design: .serif))
                        Text(resultado.ubicacion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(fragmento(resultado.texto, buscado: consulta))
                            .font(.subheadline)
                            .lineLimit(4)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Citas")
        .searchable(text: $consulta, prompt: "Frase o palabras")
        .onSubmit(of: .search) { buscar() }
        .navigationDestination(for: ResultadoCita.self) { resultado in
            ExtraccionView(resultado: resultado)
        }
        .alert(
            "Citas",
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

    private func buscar() {
        do {
            resultados = try store.buscarCitas(consulta)
        } catch {
            mensaje = error.localizedDescription
        }
    }

    /// Fragmento de la página alrededor de la frase buscada.
    private func fragmento(_ texto: String, buscado: String) -> String {
        guard let rango = texto.range(of: buscado, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(texto.prefix(220))
        }
        let inicio = texto.index(rango.lowerBound, offsetBy: -80, limitedBy: texto.startIndex) ?? texto.startIndex
        let fin = texto.index(rango.upperBound, offsetBy: 120, limitedBy: texto.endIndex) ?? texto.endIndex
        let previo = inicio > texto.startIndex ? "…" : ""
        let posterior = fin < texto.endIndex ? "…" : ""
        return previo + String(texto[inicio..<fin]) + posterior
    }
}

/// Pantalla de extracción: el texto de la página citada, editable, listo para copiar.
struct ExtraccionView: View {
    let resultado: ResultadoCita

    @State private var cita: String

    init(resultado: ResultadoCita) {
        self.resultado = resultado
        _cita = State(initialValue: resultado.texto)
    }

    private var palabras: Int {
        cita.split { $0.isWhitespace }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(resultado.titulo)
                .font(.system(.title3, design: .serif))
            Text(resultado.ubicacion)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $cita)
                .font(.system(.body, design: .serif))
                .frame(minHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            Text("Palabras: \(palabras)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(resultado.esPaginado ? "Verifica la página en el ejemplar." : "Verifica la cita en el ejemplar.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Copiar texto") {
                copiar()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .navigationTitle("Extracción")
    }

    private func copiar() {
        #if canImport(UIKit)
        UIPasteboard.general.string = cita
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cita, forType: .string)
        #endif
    }
}
