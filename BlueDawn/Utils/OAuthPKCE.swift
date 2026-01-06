import CryptoKit
import Foundation

enum OAuthPKCE {
    static func makeCodeVerifier() -> String {
        let bytes = (0..<64).map { _ in UInt8.random(in: 0...255) }
        return base64URLEncoded(Data(bytes))
    }

    static func makeCodeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return base64URLEncoded(Data(hash))
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
