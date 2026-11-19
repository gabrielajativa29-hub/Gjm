import SwiftUI

@main
struct BibliotecaAnaliticaApp: App {
    private let library: Result<LibraryStore, Error>

    init() {
        library = Result { try LibraryStore.makeDefault() }
    }

    var body: some Scene {
        WindowGroup {
            switch library {
            case .success(let store):
                AutoresView(store: store)
            case .failure(let error):
                ContentUnavailableView(
                    "No se pudo abrir la biblioteca",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            }
        }
    }
}
