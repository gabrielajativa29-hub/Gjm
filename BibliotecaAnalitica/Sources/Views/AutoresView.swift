import SwiftUI

/// Destinos de la pantalla de inicio: autores, carpetas propias y la biblioteca completa.
enum CategoriaBiblioteca: Hashable, Identifiable {
    case freud, lacan, miller, varios
    case psiquiatriaClasica, psicopatologia, josemariaAlvarez
    case todos

    var id: Self { self }

    var titulo: String {
        switch self {
        case .freud: return "Freud"
        case .lacan: return "Lacan"
        case .miller: return "Miller"
        case .varios: return "Varios"
        case .psiquiatriaClasica: return "Psiquiatría clásica"
        case .psicopatologia: return "Psicopatología"
        case .josemariaAlvarez: return "José María Álvarez"
        case .todos: return "Todos los libros"
        }
    }

    /// Autor principal que filtra la lista. `nil` si el botón no filtra por autor.
    var grupo: AuthorGroup? {
        switch self {
        case .freud: return .freud
        case .lacan: return .lacan
        case .miller: return .miller
        case .varios: return .otros
        default: return nil
        }
    }

    /// Clave de botón propio que filtra la lista. `nil` si el botón no usa etiqueta.
    var etiqueta: String? {
        switch self {
        case .psiquiatriaClasica: return "psiquiatria-clasica"
        case .psicopatologia: return "psicopatologia"
        case .josemariaAlvarez: return "jose-maria-alvarez"
        default: return nil
        }
    }

    /// Iniciales mientras no haya foto; si no, un símbolo.
    var iniciales: String? {
        switch self {
        case .freud: return "SF"
        case .lacan: return "JL"
        case .miller: return "JAM"
        default: return nil
        }
    }

    var simbolo: String {
        switch self {
        case .varios: return "books.vertical"
        case .psiquiatriaClasica: return "stethoscope"
        case .psicopatologia: return "brain.head.profile"
        case .josemariaAlvarez: return "person.fill"
        case .todos: return "list.bullet"
        default: return "person.fill"
        }
    }

    static let todas: [CategoriaBiblioteca] = [
        .freud, .lacan, .miller, .varios,
        .psiquiatriaClasica, .psicopatologia, .josemariaAlvarez,
        .todos
    ]
}

/// Pantalla de inicio con botones circulares por autor.
struct AutoresView: View {
    let store: LibraryStore

    private let columnas = [GridItem(.adaptive(minimum: 130), spacing: 24)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columnas, spacing: 28) {
                    ForEach(CategoriaBiblioteca.todas) { categoria in
                        NavigationLink(value: categoria) {
                            BotonCircular(categoria: categoria)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Text("Diseño y dirección: Gabriela Játiva-Moyano · @psicologia.clave")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 16)
            }
            .navigationTitle("Biblioteca Analítica")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        CitasView(store: store)
                    } label: {
                        Label("Citas", systemImage: "text.magnifyingglass")
                    }
                }
            }
            .navigationDestination(for: CategoriaBiblioteca.self) { categoria in
                LibraryView(
                    store: store,
                    group: categoria.grupo,
                    etiqueta: categoria.etiqueta,
                    title: categoria.titulo
                )
            }
            .navigationDestination(for: Book.self) { book in
                BookDetailView(store: store, book: book) {}
            }
        }
    }
}

struct BotonCircular: View {
    let categoria: CategoriaBiblioteca

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                if let iniciales = categoria.iniciales {
                    Text(iniciales)
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: categoria.simbolo)
                        .font(.system(size: 36))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 120, height: 120)

            Text(categoria.titulo)
                .font(.system(.headline, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}
