import Darwin
import Foundation
import Network
import Security

struct AnnuncioUDPTuya: Sendable, Hashable {
    let ip: String
    let gwId: String
    let versione: String
}

/// Motore nativo per il controllo diretto in rete locale (TCP porta 6668) dei dispositivi Tuya:
/// supporta i protocolli **3.3** (`0x55AA` AES-ECB statico), **3.4** (`0x55AA` handshake 3-way HMAC-SHA256)
/// e **3.5** (`0x6699` handshake 3-way + AES-128-GCM con AAD).
enum ProtocolloTuyaLocale {
    static let portaControllo: Int = 6668

    /// Costruisce il dizionario Data Points (`dps`) corrispondente allo stato di una `Luce`.
    static func costruisciDPS(per luce: Luce) -> [String: Any] {
        switch luce.schemaTuya {
        case .soloInterruttore:
            return ["1": luce.accensione]
        case .lucePixel:
            var dps: [String: Any] = ["20": luce.accensione]
            guard luce.accensione else { return dps }
            dps["21"] = "colour"
            let h = Int((min(1, max(0, luce.tonalita)) * 360.0).rounded()) % 360
            let bianco = luce.modo == .bianco
            let s = bianco ? 0 : Int((min(1, max(0, luce.saturazione)) * 1000.0).rounded())
            let v = Int((max(0.01, min(1, luce.luminosita)) * 1000.0).rounded())
            dps["24"] = String(format: "%04x%04x%04x", h, s, v)
            return dps
        case .luceV2:
            var dps: [String: Any] = ["20": luce.accensione]
            guard luce.accensione else { return dps }
            switch luce.modo {
            case .bianco:
                dps["21"] = "white"
                dps["22"] = Int((10.0 + min(1, max(0, luce.luminosita)) * 990.0).rounded())
                dps["23"] = Int((min(1, max(0, luce.temperatura)) * 1000.0).rounded())
            case .colore, .effetto:
                dps["21"] = "colour"
                let h = Int((min(1, max(0, luce.tonalita)) * 360.0).rounded()) % 360
                let s = Int((min(1, max(0, luce.saturazione)) * 1000.0).rounded())
                let v = Int((max(0.01, min(1, luce.luminosita)) * 1000.0).rounded())
                dps["24"] = String(format: "%04x%04x%04x", h, s, v)
            }
            return dps
        case .luceV1:
            var dps: [String: Any] = ["1": luce.accensione]
            guard luce.accensione else { return dps }
            switch luce.modo {
            case .bianco:
                dps["2"] = "white"
                dps["3"] = Int((25.0 + min(1, max(0, luce.luminosita)) * 230.0).rounded())
                dps["4"] = Int((min(1, max(0, luce.temperatura)) * 255.0).rounded())
            case .colore, .effetto:
                dps["2"] = "colour"
                let c = luce.rgb
                let h = Int((min(1, max(0, luce.tonalita)) * 360.0).rounded()) % 360
                let s = Int((min(1, max(0, luce.saturazione)) * 255.0).rounded())
                let v = Int((max(0.01, min(1, luce.luminosita)) * 255.0).rounded())
                dps["5"] = String(format: "%02x%02x%02x%04x%02x%02x", c.r, c.g, c.b, h, s, v)
            }
            return dps
        }
    }

    /// Invia i DPS alla lampadina o striscia Tuya sulla rete Wi-Fi locale (porta 6668).
    /// Se la versione salvata non risponde, prova in cascata 3.5 → 3.4 → 3.3 e restituisce la versione funzionante.
    static func applica(_ luce: Luce) async -> (riuscito: Bool, versioneRilevata: String?) {
        guard let ip = luce.ip, !ip.isEmpty,
              let devId = luce.tuyaId, !devId.isEmpty,
              let keyStr = luce.localKey, keyStr.utf8.count == 16 else {
            return (false, nil)
        }
        let chiave = Data(keyStr.utf8)
        let dps = costruisciDPS(per: luce)

        let ordine = [luce.versioneProtocollo] + ["3.5", "3.4", "3.3"].filter { $0 != luce.versioneProtocollo }
        for versione in ordine {
            let ok: Bool
            switch versione {
            case "3.5":
                ok = await inviaV35(ip: ip, porta: luce.porta, devId: devId, localKey: chiave, dps: dps)
            case "3.4":
                ok = await inviaV34(ip: ip, porta: luce.porta, devId: devId, localKey: chiave, dps: dps)
            default:
                ok = await inviaV33(ip: ip, porta: luce.porta, devId: devId, localKey: chiave, dps: dps)
            }
            if ok { return (true, versione) }
        }
        return (false, nil)
    }

    /// Verifica se un IP sulla porta 6668 appartiene a uno specifico dispositivo Tuya provando l'handshake/query con la sua `local_key`.
    static func verificaCorrispondenza(ip: String, devId: String, localKey: String) async -> String? {
        guard localKey.utf8.count == 16 else { return nil }
        let chiave = Data(localKey.utf8)
        if await sondaV35(ip: ip, localKey: chiave) { return "3.5" }
        if await sondaV34(ip: ip, localKey: chiave) { return "3.4" }
        if await sondaV33(ip: ip, devId: devId, localKey: chiave) { return "3.3" }
        return nil
    }

    // MARK: - Protocollo 3.3 (0x000055AA, AES-128-ECB statico, CRC32)

    private static func inviaV33(ip: String, porta: Int, devId: String, localKey: Data, dps: [String: Any]) async -> Bool {
        let t = Int(Date().timeIntervalSince1970)
        let oggetto: [String: Any] = ["devId": devId, "uid": devId, "t": "\(t)", "dps": dps]
        guard let json = try? JSONSerialization.data(withJSONObject: oggetto),
              let cifrato = CrittografiaTuya.aesECBCifra(json, chiave: localKey, padding: true) else {
            return false
        }
        var payload = Data("3.3".utf8)
        payload.append(Data(repeating: 0, count: 12))
        payload.append(cifrato)
        let frame = impacchetta55AA(sequenza: 1, comando: 0x07, payload: payload, chiaveHMAC: nil)
        guard let risp = await sessioneTCP(ip: ip, porta: porta, scambio: { conn in
            await conn.inviaERicevi(frame, minByte: 20)
        }) else { return false }
        return risp.starts(with: [0x00, 0x00, 0x55, 0xAA])
    }

    private static func sondaV33(ip: String, devId: String, localKey: Data) async -> Bool {
        let t = Int(Date().timeIntervalSince1970)
        let oggetto: [String: Any] = ["gwId": devId, "devId": devId, "uid": devId, "t": "\(t)"]
        guard let json = try? JSONSerialization.data(withJSONObject: oggetto),
              let cifrato = CrittografiaTuya.aesECBCifra(json, chiave: localKey, padding: true) else {
            return false
        }
        let frame = impacchetta55AA(sequenza: 1, comando: 0x0A, payload: cifrato, chiaveHMAC: nil)
        guard let risp = await sessioneTCP(ip: ip, porta: 6668, timeout: 1.0, scambio: { conn in
            await conn.inviaERicevi(frame, minByte: 24)
        }) else { return false }
        // Controlla che la risposta DP_QUERY sia decifrabile con questa localKey
        guard risp.count > 28, risp.starts(with: [0x00, 0x00, 0x55, 0xAA]) else { return false }
        let corpo = risp.subdata(in: 20..<(risp.count - 8))
        if corpo.isEmpty { return false }
        let cifratoRisp = corpo.starts(with: Data("3.3".utf8)) ? corpo.dropFirst(15) : SubstringData(corpo)
        guard let chiaro = CrittografiaTuya.aesECBDecifra(Data(cifratoRisp), chiave: localKey, padding: true),
              let str = String(data: chiaro, encoding: .utf8) else { return false }
        return str.contains("dps") || str.contains(devId)
    }

    private static func SubstringData(_ d: Data) -> Data { d }

    // MARK: - Protocollo 3.4 (0x000055AA, Handshake 3-way 0x03/0x04/0x05 + HMAC-SHA256)

    private static func inviaV34(ip: String, porta: Int, devId: String, localKey: Data, dps: [String: Any]) async -> Bool {
        let t = Int(Date().timeIntervalSince1970)
        let oggetto: [String: Any] = ["protocol": 5, "t": t, "data": ["dps": dps]]
        guard let json = try? JSONSerialization.data(withJSONObject: oggetto) else { return false }

        return await sessioneTCP(ip: ip, porta: porta) { conn -> Bool? in
            guard let chiaveSessione = await negoziaV34(conn: conn, localKey: localKey) else { return nil }
            var chiaro = Data("3.4".utf8)
            chiaro.append(Data(repeating: 0, count: 12))
            chiaro.append(json)
            guard let cifrato = CrittografiaTuya.aesECBCifra(chiaro, chiave: chiaveSessione, padding: true) else { return nil }
            let pacchetto = impacchetta55AA(sequenza: 3, comando: 0x0D, payload: cifrato, chiaveHMAC: chiaveSessione)
            guard let risp = await conn.inviaERicevi(pacchetto, minByte: 20) else { return nil }
            return risp.starts(with: [0x00, 0x00, 0x55, 0xAA])
        } ?? false
    }

    private static func sondaV34(ip: String, localKey: Data) async -> Bool {
        await sessioneTCP(ip: ip, porta: 6668, timeout: 1.0) { conn -> Bool? in
            (await negoziaV34(conn: conn, localKey: localKey)) != nil
        } ?? false
    }

    private static func negoziaV34(conn: CanaleTCP, localKey: Data) async -> Data? {
        let nonceClient = byteCasuali(16)
        guard let p1Cifrato = CrittografiaTuya.aesECBCifra(nonceClient, chiave: localKey, padding: true) else { return nil }
        let f1 = impacchetta55AA(sequenza: 1, comando: 0x03, payload: p1Cifrato, chiaveHMAC: localKey)

        guard let r2 = await conn.inviaERicevi(f1, minByte: 60),
              r2.starts(with: [0x00, 0x00, 0x55, 0xAA]),
              r2.count >= 20 + 48 + 36 else { return nil }

        // In 3.4 la risposta ha: header(16) + retcode(4) + payload cifrato + HMAC(32) + footer(4)
        let inizioPayload = 20
        let finePayload = r2.count - 36
        guard finePayload > inizioPayload,
              let decifrato = CrittografiaTuya.aesECBDecifra(r2.subdata(in: inizioPayload..<finePayload), chiave: localKey, padding: true),
              decifrato.count >= 48 else { return nil }

        let nonceDispositivo = decifrato.prefix(16)
        let hmacRicevuto = decifrato.subdata(in: 16..<48)
        let hmacAtteso = CrittografiaTuya.hmacSHA256(nonceClient, chiave: localKey)
        guard hmacRicevuto == hmacAtteso else { return nil }

        let hmacRisposta = CrittografiaTuya.hmacSHA256(Data(nonceDispositivo), chiave: localKey)
        guard let p3Cifrato = CrittografiaTuya.aesECBCifra(hmacRisposta, chiave: localKey, padding: true) else { return nil }
        let f3 = impacchetta55AA(sequenza: 2, comando: 0x05, payload: p3Cifrato, chiaveHMAC: localKey)
        _ = await conn.inviaSenzaRisposta(f3)

        var xorBytes = Data(count: 16)
        for i in 0..<16 {
            xorBytes[i] = nonceClient[nonceClient.startIndex + i] ^ nonceDispositivo[nonceDispositivo.startIndex + i]
        }
        return CrittografiaTuya.aesECBCifra(xorBytes, chiave: localKey, padding: false)?.prefix(16).map { $0 }.withUnsafeBufferPointer { Data($0) }
    }

    // MARK: - Protocollo 3.5 (0x00006699, Handshake 3-way + AES-128-GCM con AAD)

    private static func inviaV35(ip: String, porta: Int, devId: String, localKey: Data, dps: [String: Any]) async -> Bool {
        let t = Int(Date().timeIntervalSince1970)
        let oggetto: [String: Any] = ["protocol": 5, "t": t, "data": ["dps": dps]]
        guard let json = try? JSONSerialization.data(withJSONObject: oggetto) else { return false }

        return await sessioneTCP(ip: ip, porta: porta) { conn -> Bool? in
            guard let chiaveSessione = await negoziaV35(conn: conn, localKey: localKey) else { return nil }
            var chiaro = Data("3.5".utf8)
            chiaro.append(Data(repeating: 0, count: 12))
            chiaro.append(json)
            guard let fComando = impacchetta6699(sequenza: 3, comando: 0x0D, payload: chiaro, chiave: chiaveSessione) else { return nil }
            guard let risp = await conn.inviaERicevi(fComando, minByte: 22) else { return nil }
            return risp.starts(with: [0x00, 0x00, 0x66, 0x99])
        } ?? false
    }

    private static func sondaV35(ip: String, localKey: Data) async -> Bool {
        await sessioneTCP(ip: ip, porta: 6668, timeout: 1.0) { conn -> Bool? in
            (await negoziaV35(conn: conn, localKey: localKey)) != nil
        } ?? false
    }

    private static func negoziaV35(conn: CanaleTCP, localKey: Data) async -> Data? {
        let nonceClient = byteCasuali(16)
        guard let f1 = impacchetta6699(sequenza: 1, comando: 0x03, payload: nonceClient, chiave: localKey),
              let r2 = await conn.inviaERicevi(f1, minByte: 50),
              let decifrato = spacchetta6699(r2, chiave: localKey) else { return nil }

        // Risposta 0x04: 4 byte retcode (0) + 16 byte device_nonce + 32 byte HMAC(client_nonce)
        let corpo = decifrato.count >= 52 ? decifrato.dropFirst(4) : SubstringData(decifrato)
        guard corpo.count >= 48 else { return nil }
        let nonceDispositivo = Data(corpo.prefix(16))
        let hmacRicevuto = Data(corpo.dropFirst(16).prefix(32))
        guard hmacRicevuto == CrittografiaTuya.hmacSHA256(nonceClient, chiave: localKey) else { return nil }

        let hmacConferma = CrittografiaTuya.hmacSHA256(nonceDispositivo, chiave: localKey)
        if let f3 = impacchetta6699(sequenza: 2, comando: 0x05, payload: hmacConferma, chiave: localKey) {
            _ = await conn.inviaSenzaRisposta(f3)
        }

        var xorBytes = Data(count: 16)
        for i in 0..<16 {
            xorBytes[i] = nonceClient[i] ^ nonceDispositivo[i]
        }
        let ivDerivazione = nonceClient.prefix(12)
        guard let (cifratoSessione, _) = CrittografiaTuya.aesGCMCifra(xorBytes, chiave: localKey, iv: Data(ivDerivazione)) else {
            return nil
        }
        return Data(cifratoSessione.prefix(16))
    }

    // MARK: - Costruzione frame 0x55AA e 0x6699

    private static func impacchetta55AA(sequenza: UInt32, comando: UInt32, payload: Data, chiaveHMAC: Data?) -> Data {
        let lungCoda = (chiaveHMAC != nil ? 32 : 4) + 4
        var frame = Data([0x00, 0x00, 0x55, 0xAA])
        frame.appendUInt32BE(sequenza)
        frame.appendUInt32BE(comando)
        frame.appendUInt32BE(UInt32(payload.count + lungCoda))
        frame.append(payload)
        if let chiaveHMAC {
            let mac = CrittografiaTuya.hmacSHA256(frame, chiave: chiaveHMAC)
            frame.append(mac)
        } else {
            let crc = CrittografiaTuya.crc32(frame)
            frame.appendUInt32BE(crc)
        }
        frame.append(contentsOf: [0x00, 0x00, 0xAA, 0x55])
        return frame
    }

    private static func impacchetta6699(sequenza: UInt32, comando: UInt32, payload: Data, chiave: Data) -> Data? {
        let iv = byteCasuali(12)
        let lunghezza = UInt32(12 + payload.count + 16)
        var aad = Data([0x00, 0x00])
        aad.appendUInt32BE(sequenza)
        aad.appendUInt32BE(comando)
        aad.appendUInt32BE(lunghezza)

        guard let (cifrato, tag) = CrittografiaTuya.aesGCMCifra(payload, chiave: chiave, iv: iv, aad: aad) else {
            return nil
        }
        var frame = Data([0x00, 0x00, 0x66, 0x99])
        frame.append(aad)
        frame.append(iv)
        frame.append(cifrato)
        frame.append(tag)
        frame.append(contentsOf: [0x00, 0x00, 0x99, 0x66])
        return frame
    }

    private static func spacchetta6699(_ dati: Data, chiave: Data) -> Data? {
        guard dati.count >= 4 + 14 + 12 + 16 + 4,
              dati.starts(with: [0x00, 0x00, 0x66, 0x99]),
              let lunghezza = dati.uint32BE(a: 14) else { return nil }
        let fineContenuto = 18 + Int(lunghezza)
        guard fineContenuto <= dati.count - 4, lunghezza >= 28 else { return nil }
        let aad = dati.subdata(in: 4..<18)
        let iv = dati.subdata(in: 18..<30)
        let cifrato = dati.subdata(in: 30..<(fineContenuto - 16))
        let tag = dati.subdata(in: (fineContenuto - 16)..<fineContenuto)
        return CrittografiaTuya.aesGCMDecifra(cifrato, tag: tag, chiave: chiave, iv: iv, aad: aad)
    }

    private static func byteCasuali(_ n: Int) -> Data {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return Data(b)
    }

    // MARK: - Ascolto passivo annunci UDP Tuya (6666 chiaro / 6667 cifrato AES-ECB)

    static func ascoltaAnnunciUDP(durata: TimeInterval = 1.3) async -> [AnnuncioUDPTuya] {
        let chiaveUDP = CrittografiaTuya.md5(Data("yGAdlopoPVldABfn".utf8))
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var trovati: [String: AnnuncioUDPTuya] = [:]
                let porte: [UInt16] = [6666, 6667]
                var sockets: [Int32] = []

                for p in porte {
                    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                    guard fd >= 0 else { continue }
                    var riusa: Int32 = 1
                    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &riusa, socklen_t(MemoryLayout<Int32>.size))
                    var tv = timeval(tv_sec: 0, tv_usec: 180_000)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                    var addr = sockaddr_in()
                    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = p.bigEndian
                    addr.sin_addr.s_addr = 0
                    let ok = withUnsafePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                    if ok == 0 {
                        sockets.append(fd)
                    } else {
                        close(fd)
                    }
                }
                defer { sockets.forEach { close($0) } }
                guard !sockets.isEmpty else {
                    cont.resume(returning: [])
                    return
                }

                let fine = Date().addingTimeInterval(durata)
                var buf = [UInt8](repeating: 0, count: 1024)
                while Date() < fine {
                    for fd in sockets {
                        let n = recv(fd, &buf, buf.count, 0)
                        guard n > 28 else { continue }
                        let pacchetto = Data(buf[0..<n])
                        let corpo = pacchetto.subdata(in: 20..<(n - 8))
                        let jsonDati = CrittografiaTuya.aesECBDecifra(corpo, chiave: chiaveUDP, padding: true) ?? corpo
                        if let ogg = try? JSONSerialization.jsonObject(with: jsonDati) as? [String: Any],
                           let ip = ogg["ip"] as? String,
                           let gwId = ogg["gwId"] as? String {
                            let ver = (ogg["version"] as? String) ?? "3.3"
                            trovati[gwId] = AnnuncioUDPTuya(ip: ip, gwId: gwId, versione: ver)
                        }
                    }
                }
                cont.resume(returning: Array(trovati.values))
            }
        }
    }

    // MARK: - Sessione TCP persistente per handshake multi-step

    private static func sessioneTCP<R>(
        ip: String,
        porta: Int,
        timeout: TimeInterval = 1.8,
        scambio: (CanaleTCP) async -> R?
    ) async -> R? {
        guard let nwPorta = NWEndpoint.Port(rawValue: UInt16(clamping: porta)) else { return nil }
        let canale = CanaleTCP(ip: ip, porta: nwPorta)
        guard await canale.apri(timeout: timeout) else {
            canale.chiudi()
            return nil
        }
        defer { canale.chiudi() }
        return await scambio(canale)
    }
}

final class CanaleTCP: @unchecked Sendable {
    private let conn: NWConnection
    private let coda = DispatchQueue(label: "it.domus.tuya.tcp.\(UUID().uuidString)")

    init(ip: String, porta: NWEndpoint.Port) {
        conn = NWConnection(host: NWEndpoint.Host(ip), port: porta, using: .tcp)
    }

    func apri(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { cont in
            let guardia = ScatolaCompletamento<Bool>()
            let fine: (Bool) -> Void = { ok in
                guard guardia.completaUnaVolta() else { return }
                cont.resume(returning: ok)
            }
            coda.asyncAfter(deadline: .now() + timeout) { fine(false) }
            conn.stateUpdateHandler = { stato in
                switch stato {
                case .ready: fine(true)
                case .failed, .cancelled: fine(false)
                default: break
                }
            }
            conn.start(queue: coda)
        }
    }

    func inviaERicevi(_ dati: Data, minByte: Int, timeout: TimeInterval = 1.2) async -> Data? {
        await withCheckedContinuation { cont in
            let guardia = ScatolaCompletamento<Data?>()
            let fine: (Data?) -> Void = { d in
                guard guardia.completaUnaVolta() else { return }
                cont.resume(returning: d)
            }
            coda.asyncAfter(deadline: .now() + timeout) { fine(nil) }
            conn.send(content: dati, completion: .contentProcessed { err in
                if err != nil {
                    fine(nil)
                    return
                }
                self.conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { ricevuti, _, _, rErr in
                    if rErr != nil || (ricevuti?.count ?? 0) < minByte {
                        fine(nil)
                    } else {
                        fine(ricevuti)
                    }
                }
            })
        }
    }

    func inviaSenzaRisposta(_ dati: Data) async -> Bool {
        await withCheckedContinuation { cont in
            let guardia = ScatolaCompletamento<Bool>()
            let fine: (Bool) -> Void = { ok in
                guard guardia.completaUnaVolta() else { return }
                cont.resume(returning: ok)
            }
            coda.asyncAfter(deadline: .now() + 0.6) { fine(false) }
            conn.send(content: dati, completion: .contentProcessed { err in
                fine(err == nil)
            })
        }
    }

    func chiudi() {
        conn.cancel()
    }
}

/// Esecutore rapido condiviso tra App e Widget Extension:
/// per Magic Home usa TCP 5577 locale; per Tuya prova prima la LAN (se ha IP + local_key) e cade automaticamente sul Cloud.
enum ControlloRapido {
    static func applica(_ luce: Luce, credenzialiTuya: CredenzialiTuya) async -> (riuscito: Bool, viaLocale: Bool, versioneTuya: String?) {
        switch luce.marca {
        case .magicHome:
            let ok = await ProtocolloMagicHome.applica(luce)
            return (ok, ok, nil)
        case .tuya:
            let (okLocale, ver) = await ProtocolloTuyaLocale.applica(luce)
            if okLocale {
                return (true, true, ver)
            }
            let okCloud = await ProtocolloTuyaCloud.condiviso.inviaStato(luce, credenziali: credenzialiTuya)
            return (okCloud, false, nil)
        }
    }
}
