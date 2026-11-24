import CommonCrypto
import CryptoKit
import Foundation

/// Primitive crittografiche native per Tuya Cloud OpenAPI (HMAC-SHA256, SHA-256)
/// e Tuya LAN locale v3.3 / v3.4 / v3.5 (AES-128-ECB, AES-128-GCM, MD5, CRC32).
enum CrittografiaTuya {
    static func sha256Esadecimale(_ dati: Data) -> String {
        SHA256.hash(data: dati).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ dati: Data) -> Data {
        Data(SHA256.hash(data: dati))
    }

    static func md5(_ dati: Data) -> Data {
        Data(Insecure.MD5.hash(data: dati))
    }

    static func hmacSHA256(_ dati: Data, chiave: Data) -> Data {
        let codice = HMAC<SHA256>.authenticationCode(for: dati, using: SymmetricKey(data: chiave))
        return Data(codice)
    }

    static func hmacSHA256EsadecimaleMaiuscolo(_ testo: String, segreto: String) -> String {
        let firma = hmacSHA256(Data(testo.utf8), chiave: Data(segreto.utf8))
        return firma.map { String(format: "%02X", $0) }.joined()
    }

    /// CRC-32 standard IEEE 802.3 usato nei pacchetti Tuya v3.3 (`0x000055AA`).
    static func crc32(_ dati: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in dati {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }

    /// Cifratura AES-128-ECB tramite CommonCrypto (con o senza PKCS#7 padding).
    static func aesECBCifra(_ dati: Data, chiave: Data, padding: Bool = true) -> Data? {
        guard chiave.count == kCCKeySizeAES128 else { return nil }
        let opzioni = CCOptions(kCCOptionECBMode) | (padding ? CCOptions(kCCOptionPKCS7Padding) : 0)
        let capienza = dati.count + kCCBlockSizeAES128
        var uscita = Data(count: capienza)
        var scritti: size_t = 0

        let stato = uscita.withUnsafeMutableBytes { outPtr in
            dati.withUnsafeBytes { inPtr in
                chiave.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        opzioni,
                        keyPtr.baseAddress,
                        kCCKeySizeAES128,
                        nil,
                        inPtr.baseAddress,
                        dati.count,
                        outPtr.baseAddress,
                        capienza,
                        &scritti
                    )
                }
            }
        }
        guard stato == kCCSuccess else { return nil }
        uscita.count = scritti
        return uscita
    }

    /// Decifratura AES-128-ECB tramite CommonCrypto.
    static func aesECBDecifra(_ dati: Data, chiave: Data, padding: Bool = true) -> Data? {
        guard chiave.count == kCCKeySizeAES128, !dati.isEmpty else { return nil }
        let opzioni = CCOptions(kCCOptionECBMode) | (padding ? CCOptions(kCCOptionPKCS7Padding) : 0)
        let capienza = dati.count + kCCBlockSizeAES128
        var uscita = Data(count: capienza)
        var scritti: size_t = 0

        let stato = uscita.withUnsafeMutableBytes { outPtr in
            dati.withUnsafeBytes { inPtr in
                chiave.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        opzioni,
                        keyPtr.baseAddress,
                        kCCKeySizeAES128,
                        nil,
                        inPtr.baseAddress,
                        dati.count,
                        outPtr.baseAddress,
                        capienza,
                        &scritti
                    )
                }
            }
        }
        guard stato == kCCSuccess else { return nil }
        uscita.count = scritti
        return uscita
    }

    /// Cifratura autenticata AES-128-GCM per il protocollo Tuya v3.5 (`0x00006699`).
    static func aesGCMCifra(_ dati: Data, chiave: Data, iv: Data, aad: Data? = nil) -> (cifrato: Data, tag: Data)? {
        guard chiave.count == 16, let nonce = try? AES.GCM.Nonce(data: iv) else { return nil }
        let simmetrica = SymmetricKey(data: chiave)
        let sigillato: AES.GCM.SealedBox?
        if let aad {
            sigillato = try? AES.GCM.seal(dati, using: simmetrica, nonce: nonce, authenticating: aad)
        } else {
            sigillato = try? AES.GCM.seal(dati, using: simmetrica, nonce: nonce)
        }
        guard let box = sigillato else { return nil }
        return (Data(box.ciphertext), Data(box.tag))
    }

    /// Decifratura autenticata AES-128-GCM per il protocollo Tuya v3.5 (`0x00006699`).
    static func aesGCMDecifra(_ cifrato: Data, tag: Data, chiave: Data, iv: Data, aad: Data? = nil) -> Data? {
        guard chiave.count == 16,
              let nonce = try? AES.GCM.Nonce(data: iv),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: cifrato, tag: tag) else {
            return nil
        }
        let simmetrica = SymmetricKey(data: chiave)
        if let aad {
            return try? AES.GCM.open(box, using: simmetrica, authenticating: aad)
        } else {
            return try? AES.GCM.open(box, using: simmetrica)
        }
    }

    /// Cifratura/decifratura AES-128-CBC senza padding per lampadine BroadLink / Magic Home (`0x60C8`).
    static func aesCBC(_ dati: Data, chiave: Data, iv: Data, cifra: Bool) -> Data? {
        guard chiave.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128, !dati.isEmpty else { return nil }
        let capienza = dati.count + kCCBlockSizeAES128
        var uscita = Data(count: capienza)
        var scritti: size_t = 0
        let stato = uscita.withUnsafeMutableBytes { outPtr in
            dati.withUnsafeBytes { inPtr in
                chiave.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(cifra ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            0,
                            keyPtr.baseAddress,
                            kCCKeySizeAES128,
                            ivPtr.baseAddress,
                            inPtr.baseAddress,
                            dati.count,
                            outPtr.baseAddress,
                            capienza,
                            &scritti
                        )
                    }
                }
            }
        }
        guard stato == kCCSuccess else { return nil }
        uscita.count = scritti
        return uscita
    }
}

extension Data {
    mutating func appendUInt32BE(_ valore: UInt32) {
        var be = valore.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func uint32BE(a offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let b0 = UInt32(self[startIndex + offset]) << 24
        let b1 = UInt32(self[startIndex + offset + 1]) << 16
        let b2 = UInt32(self[startIndex + offset + 2]) << 8
        let b3 = UInt32(self[startIndex + offset + 3])
        return b0 | b1 | b2 | b3
    }
}
