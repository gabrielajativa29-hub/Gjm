import SwiftUI

/// Carpetas de Google Drive de acceso directo. Cada botón abre la carpeta en el navegador.
/// Las carpetas son de terceros o compartidas: la app solo enlaza, no descarga nada.
struct CarpetaDrive: Identifiable {
    let id: String
    let titulo: String
    let icono: String
    let url: URL
}

enum CarpetasDrive {
    static let todas: [CarpetaDrive] = [
        CarpetaDrive(
            id: "mapas-mentales",
            titulo: "Mapas mentales",
            icono: "brain.head.profile",
            url: URL(string: "https://drive.google.com/drive/folders/1sbEttb7d7oaw4Nb_PS28L3MzEjWdvnM7")!
        ),
        CarpetaDrive(
            id: "psicopatologia",
            titulo: "Psicopatología",
            icono: "heart.text.square",
            url: URL(string: "https://drive.google.com/drive/folders/1uvk6FfR-zYJwocCP4OCA8WFyF87BcxG7")!
        ),
        CarpetaDrive(
            id: "varios",
            titulo: "Varios",
            icono: "tray.full",
            url: URL(string: "https://drive.google.com/drive/folders/1_A-slX6kdXsmFD67DmFJPhc9YLFD5Y-r")!
        ),
        CarpetaDrive(
            id: "textos-perversion",
            titulo: "Textos perversión",
            icono: "text.book.closed",
            url: URL(string: "https://drive.google.com/drive/folders/10LLLfGVyfAk0djbenE4rO4nepmawl4WA")!
        )
    ]
}

struct CarpetasView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(CarpetasDrive.todas) { carpeta in
                        Link(destination: carpeta.url) {
                            Label(carpeta.titulo, systemImage: carpeta.icono)
                                .font(.system(.body, design: .serif))
                        }
                    }
                } footer: {
                    Text("Se abren en el navegador, en Google Drive. Los archivos no se descargan a la biblioteca.")
                }
            }
            .navigationTitle("Carpetas")
        }
    }
}
