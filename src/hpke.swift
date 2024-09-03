import CryptoKit
import Foundation

// This needs to be manually synced with the enum in args.h
enum PrivateKeyFormat: Int {
    case all
    case PEM
    case DER
    case X963
}

enum HPKEWrapperError: Error {
    case invalidPrivateKeyFormat(Int)
    case invalidWrappedKey(String)
    case invalidPrivateKey(String)
}

@objc public class HPKEWrapper: NSObject {
    @objc(unwrapPrivateKey:format:encryptedRequest:wrappedKey:error:) public static func unwrapKey(
        rawPrivateKey: Data,
        rawFormat: Int,
        encryptedRequest: Data,
        wrappedKey: Data
    ) throws -> Data {
        guard wrappedKey.count == 0x30 else {
            throw HPKEWrapperError.invalidWrappedKey("Wrapped key is not 0x30 bytes")
        }

        guard let format = PrivateKeyFormat(rawValue: rawFormat) else {
            throw HPKEWrapperError.invalidPrivateKeyFormat(rawFormat)
        }

        var privateKey: (any CryptoKit.HPKEDiffieHellmanPrivateKey)? = nil
        if format == .all || format == .PEM {
            if let privateKeyString = String(data: rawPrivateKey, encoding: .utf8) {
                privateKey = try? P256.KeyAgreement.PrivateKey(pemRepresentation: privateKeyString)
            }
        }
        else if privateKey == nil && (format == .all || format == .DER) {
            privateKey = try? P256.KeyAgreement.PrivateKey(derRepresentation: rawPrivateKey)
        }
        else if privateKey == nil && (format == .all || format == .X963) {
            privateKey = try? P256.KeyAgreement.PrivateKey(x963Representation: rawPrivateKey)
        }

        if privateKey == nil {
            throw HPKEWrapperError.invalidPrivateKey("Invalid private key")
        }

        var recipient = try CryptoKit.HPKE.Recipient.init(
            privateKey: privateKey!,
            ciphersuite: HPKE.Ciphersuite.P256_SHA256_AES_GCM_256,
            info: Data(),
            encapsulatedKey: encryptedRequest
        )

        return try recipient.open(wrappedKey)
    }
}
