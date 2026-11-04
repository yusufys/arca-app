import Foundation
import CryptoKit
import CommonCrypto

/// Device-local password verifier. The password is never persisted or used by a network request.
public struct ConsentPasswordVerifier: Codable, Sendable, Equatable {
    public let salt: Data
    public let digest: Data
    public let iterations: UInt32

    public init(password: String) throws {
        guard password.count >= 12, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArcaCryptoError.invalidPassphrase
        }
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else { throw ArcaCryptoError.encryptionFailed }
        self.salt = Data(saltBytes); self.iterations = 210_000
        self.digest = try Self.derive(password, salt: self.salt, iterations: self.iterations)
    }

    public func verify(_ password: String) throws -> Bool {
        guard salt.count == 32, digest.count == 32, iterations == 210_000 else { throw ArcaCryptoError.authenticationFailed }
        let candidate = try Self.derive(password, salt: salt, iterations: iterations)
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, digest) { difference |= a ^ b }
        return difference == 0
    }

    private static func derive(_ password: String, salt: Data, iterations: UInt32) throws -> Data {
        let input = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: 32)
        let status = input.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), input.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &output, output.count)
            }
        }
        guard status == kCCSuccess else { throw ArcaCryptoError.encryptionFailed }
        return Data(output)
    }
}
