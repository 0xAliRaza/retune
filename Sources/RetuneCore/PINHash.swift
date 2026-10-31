import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Parental PIN hashing: PBKDF2-HMAC-SHA256 with a random per-PIN salt, stored as
/// `pbkdf2-sha256$<iterations>$<salt hex>$<hash hex>`.
///
/// This slows guessing, but a short numeric PIN stored in a user-editable file is a family deterrent,
/// not a security boundary.
enum PINHash {
    private static let scheme = "pbkdf2-sha256"
    private static let iterations: UInt32 = 310_000
    private static let saltLength = 16
    private static let hashLength = 32

    static func make(_ pin: String) -> String {
        var salt = [UInt8](repeating: 0, count: saltLength)
        // Never falls back to a fixed salt: a failed generator is a fatal platform fault.
        precondition(SecRandomCopyBytes(kSecRandomDefault, saltLength, &salt) == errSecSuccess)
        return encode(salt: salt, iterations: iterations, hash: derive(pin, salt: salt, iterations: iterations))
    }

    static func verify(_ pin: String, against stored: String) -> Bool {
        if isLegacy(stored) { return constantTimeEquals(Array(legacyHash(pin).utf8), Array(stored.utf8)) }
        let parts = stored.split(separator: "$").map(String.init)
        guard parts.count == 4, parts[0] == scheme, let rounds = UInt32(parts[1]), rounds > 0,
              let salt = bytes(hex: parts[2]), let expected = bytes(hex: parts[3]) else { return false }
        return constantTimeEquals(derive(pin, salt: salt, iterations: rounds, length: expected.count), expected)
    }

    /// Early builds stored a plain SHA-256 with a fixed prefix.
    static func isLegacy(_ stored: String) -> Bool { !stored.hasPrefix(scheme + "$") }

    static func legacyHash(_ pin: String) -> String {
        hex(Array(SHA256.hash(data: Data("lumen.parental.\(pin)".utf8))))
    }

    private static func derive(_ pin: String, salt: [UInt8], iterations: UInt32, length: Int = hashLength) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: length)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pin, pin.utf8.count, salt, salt.count,
                                          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &output, output.count)
        precondition(status == kCCSuccess)
        return output
    }

    private static func encode(salt: [UInt8], iterations: UInt32, hash: [UInt8]) -> String {
        "\(scheme)$\(iterations)$\(hex(salt))$\(hex(hash))"
    }

    private static func hex(_ value: [UInt8]) -> String {
        value.map { String(format: "%02x", $0) }.joined()
    }

    private static func bytes(hex: String) -> [UInt8]? {
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
        var output: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            output.append(byte)
            index = next
        }
        return output
    }

    private static func constantTimeEquals(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
