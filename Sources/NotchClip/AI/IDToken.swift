import CryptoKit
import Foundation
import Security

/// Verifies an OpenID Connect ID token (RS256) against OpenAI's published keys.
enum IDToken {
    static let issuer = "https://auth.openai.com"
    static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!

    struct Claims {
        let subject: String
        let email: String?
    }

    static func verify(_ token: String, clientID: String, nonce: String, now: Date = Date()) async throws -> Claims {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let headerData = base64URLDecode(parts[0]), let payloadData = base64URLDecode(parts[1]),
              let signature = base64URLDecode(parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              header["alg"] as? String == "RS256", let kid = header["kid"] as? String else {
            throw AIError.server("ChatGPT sent back an identity we couldn't read. Please try again.")
        }

        let key = try await publicKey(kid: kid)
        let signed = Data("\(parts[0]).\(parts[1])".utf8)
        guard SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil) else {
            throw AIError.server("ChatGPT's identity check failed. Please try again.")
        }

        let audience = (claims["aud"] as? [String]) ?? [(claims["aud"] as? String) ?? ""]
        let expiry = (claims["exp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        guard claims["iss"] as? String == issuer, audience.contains(clientID),
              expiry > now.addingTimeInterval(-60), claims["nonce"] as? String == nonce,
              let subject = claims["sub"] as? String else {
            throw AIError.server("ChatGPT's identity didn't match this sign-in. Please try again.")
        }
        return Claims(subject: subject, email: claims["email"] as? String)
    }

    /// Reads a claim from an ID token without verifying it (only for tokens verified earlier).
    static func unverifiedClaim(_ name: String, in token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let data = base64URLDecode(String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims[name] as? String
    }

    static func discovery() async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(from: discoveryURL)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func publicKey(kid: String) async throws -> SecKey {
        guard let jwksString = try await discovery()["jwks_uri"] as? String, let jwksURL = URL(string: jwksString) else {
            throw AIError.server("Couldn't reach OpenAI's sign-in service.")
        }
        let (data, _) = try await URLSession.shared.data(from: jwksURL)
        let keys = ((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["keys"] as? [[String: Any]]) ?? []
        guard let jwk = keys.first(where: { $0["kid"] as? String == kid }),
              let modulus = (jwk["n"] as? String).flatMap(base64URLDecode),
              let exponent = (jwk["e"] as? String).flatMap(base64URLDecode) else {
            throw AIError.server("OpenAI's signing key wasn't found.")
        }
        let der = DER.sequence(DER.integer(modulus) + DER.integer(exponent))
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil) else {
            throw AIError.server("OpenAI's signing key couldn't be loaded.")
        }
        return key
    }

    static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Just enough DER to build a PKCS#1 RSA public key from a JWK.
private enum DER {
    static func integer(_ bytes: Data) -> Data {
        var value = Data(bytes.drop { $0 == 0 })
        if let first = value.first, first & 0x80 != 0 { value.insert(0, at: 0) }
        if value.isEmpty { value = Data([0]) }
        return Data([0x02]) + length(value.count) + value
    }

    static func sequence(_ content: Data) -> Data {
        Data([0x30]) + length(content.count) + content
    }

    private static func length(_ count: Int) -> Data {
        guard count >= 0x80 else { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
