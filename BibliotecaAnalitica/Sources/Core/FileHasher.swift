import CryptoKit
import Foundation

enum FileHasher {
    /// Huella SHA-256 del contenido, en hexadecimal minúsculas.
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
