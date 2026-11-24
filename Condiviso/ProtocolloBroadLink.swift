import Darwin
import Foundation

struct ScopertaBroadLink: Sendable, Hashable {
    let ip: String
    let mac: String           // Formato esadecimale "A043B0476472" (ordine standard)
    let devType: UInt16
    let nome: String
    let bloccata: Bool
}

struct StatoBroadLink: Sendable {
    let accesa: Bool
    let luminosita: Double
    let temperatura: Double
    let tonalita: Double
    let saturazione: Double
    let modoBianco: Bool
}

/// Motore nativo per lampadine Magic Home (魔法家 `id1399499332`) basate su protocollo BroadLink LB1 (`0x60C8` / UDP porta 80).
/// Supporta scoperta broadcast + scansione unicast `/24` (funziona su iOS con SideStore senza entitlement Multicast),
/// lettura stato e controllo di accensione, luminosità, temperatura bianco (2700K–6500K) e colore RGB/HSB.
enum ProtocolloBroadLink {
    static let portaControllo: UInt16 = 80
    private static let chiaveIniziale = Data([0x09, 0x76, 0x28, 0x34, 0x3F, 0xE9, 0x9E, 0x23, 0x76, 0x5C, 0x15, 0x13, 0xAC, 0xCF, 0x8B, 0x02])
    private static let iv = Data([0x56, 0x2E, 0x17, 0x99, 0x6D, 0x09, 0x3D, 0x28, 0xDD, 0xB3, 0xBA, 0x69, 0x5A, 0x2E, 0x6F, 0x58])

    /// Scopre tutte le lampadine BroadLink / Magic Home sulla sottorete Wi-Fi tramite broadcast + sonda unicast UDP porta 80.
    static func scopri(ipLocale: String, prefisso: String, broadcast: String, durata: TimeInterval = 1.6) async -> [ScopertaBroadLink] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else {
                    cont.resume(returning: [])
                    return
                }
                defer { close(fd) }

                var abilita: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &abilita, socklen_t(MemoryLayout<Int32>.size))
                var tv = timeval(tv_sec: 0, tv_usec: 180_000)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // Bind su porta effimera per conoscere la porta sorgente da inserire nel pacchetto discovery BroadLink
                var locale = sockaddr_in()
                locale.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                locale.sin_family = sa_family_t(AF_INET)
                locale.sin_port = 0
                _ = ipLocale.withCString { inet_pton(AF_INET, $0, &locale.sin_addr) }
                _ = withUnsafePointer(to: &locale) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                var bound = sockaddr_in()
                var bLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                _ = withUnsafeMutablePointer(to: &bound) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        getsockname(fd, sa, &bLen)
                    }
                }
                let portaLocale = UInt16(bigEndian: bound.sin_port)

                let pacchetto = costruisciDiscovery(ipLocale: ipLocale, portaLocale: portaLocale)

                func invia(a ip: String) {
                    var dest = sockaddr_in()
                    dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    dest.sin_family = sa_family_t(AF_INET)
                    dest.sin_port = portaControllo.bigEndian
                    guard ip.withCString({ inet_pton(AF_INET, $0, &dest.sin_addr) }) == 1 else { return }
                    _ = pacchetto.withUnsafeBytes { pPtr in
                        withUnsafePointer(to: &dest) { dPtr in
                            dPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                sendto(fd, pPtr.baseAddress, pPtr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                }

                // 1. Broadcast subnet e globale
                invia(a: broadcast)
                invia(a: "255.255.255.255")

                // 2. Unicast rapido su tutta la /24 (aggira il blocco Multicast/Broadcast su SideStore gratuito!)
                for host in 1...254 {
                    let candidato = "\(prefisso).\(host)"
                    if candidato != ipLocale {
                        invia(a: candidato)
                    }
                }

                var trovati: [String: ScopertaBroadLink] = [:]
                let scadenza = Date().addingTimeInterval(durata)
                var buf = [UInt8](repeating: 0, count: 512)
                while Date() < scadenza {
                    var mittente = sockaddr_in()
                    var mLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let letti = buf.withUnsafeMutableBytes { bPtr in
                        withUnsafeMutablePointer(to: &mittente) { mPtr in
                            mPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                recvfrom(fd, bPtr.baseAddress, bPtr.count, 0, sa, &mLen)
                            }
                        }
                    }
                    guard letti >= 0x42 else { continue }
                    var ipChars = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var addr = mittente.sin_addr
                    inet_ntop(AF_INET, &addr, &ipChars, socklen_t(INET_ADDRSTRLEN))
                    let ip = String(cString: ipChars)

                    let devType = UInt16(buf[0x34]) | (UInt16(buf[0x35]) << 8)
                    // MAC in ordine inverso nei byte 0x3A...0x3F
                    let macBytes = (0..<6).map { buf[0x3F - $0] }
                    let macHex = macBytes.map { String(format: "%02X", $0) }.joined()
                    let nomeSlice = buf[0x40..<min(letti, 0x7E)].prefix { $0 != 0 }
                    let nomeGrezzo = String(bytes: nomeSlice, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let nome = nomeGrezzo.isEmpty ? "Lampadina Magic Home" : nomeGrezzo
                    let bloccata = letti > 0x7F ? (buf[0x7F] != 0) : false

                    trovati[ip] = ScopertaBroadLink(ip: ip, mac: macHex, devType: devType, nome: nome, bloccata: bloccata)
                }

                cont.resume(returning: Array(trovati.values))
            }
        }
    }

    static func applica(_ luce: Luce) async -> Bool {
        guard let ip = luce.ip, !ip.isEmpty else { return false }
        let mac = byteMAC(da: luce.mac)
        var payload: [String: Any] = ["pwr": luce.accensione ? 1 : 0]
        if luce.accensione {
            payload["brightness"] = max(1, min(100, Int((luce.luminosita * 100.0).rounded())))
            switch luce.modo {
            case .bianco:
                payload["bulb_colormode"] = 1
                payload["colortemp"] = max(2700, min(6500, luce.kelvin))
            case .colore, .effetto:
                let c = luce.rgb
                payload["bulb_colormode"] = 0
                payload["hue"] = Int((min(1, max(0, luce.tonalita)) * 360.0).rounded()) % 360
                payload["saturation"] = max(0, min(100, Int((luce.saturazione * 100.0).rounded())))
                payload["red"] = Int(c.r)
                payload["green"] = Int(c.g)
                payload["blue"] = Int(c.b)
            }
        }
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        return await eseguiScambio(ip: ip, mac: mac, flag: 2, json: json) != nil
    }

    static func leggiStato(ip: String, mac macStr: String?) async -> StatoBroadLink? {
        let mac = byteMAC(da: macStr)
        guard let dati = await eseguiScambio(ip: ip, mac: mac, flag: 1, json: Data("{}".utf8)),
              let ogg = try? JSONSerialization.jsonObject(with: dati) as? [String: Any] else {
            return nil
        }
        let pwr = (ogg["pwr"] as? Int ?? 0) != 0
        let lum = Double(ogg["brightness"] as? Int ?? 80) / 100.0
        let tempK = Double(ogg["colortemp"] as? Int ?? 3500)
        let temp = min(1, max(0, (tempK - 2700.0) / 3800.0))
        let h = min(1, max(0, Double(ogg["hue"] as? Int ?? 0) / 360.0))
        let s = min(1, max(0, Double(ogg["saturation"] as? Int ?? 100) / 100.0))
        let modoBianco = (ogg["bulb_colormode"] as? Int ?? 1) == 1
        return StatoBroadLink(accesa: pwr, luminosita: max(0.01, lum), temperatura: temp, tonalita: h, saturazione: s, modoBianco: modoBianco)
    }

    // MARK: - Framing UDP BroadLink (0x65 Auth + 0x6A LB1 JSON)

    private static func eseguiScambio(ip: String, mac: [UInt8], flag: UInt8, json: Data) async -> Data? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else {
                    cont.resume(returning: nil)
                    return
                }
                defer { close(fd) }

                var tv = timeval(tv_sec: 1, tv_usec: 200_000)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // 1. Auth (cmd 0x65)
                var authPayload = Data(count: 0x50)
                for i in 0x04...0x12 { authPayload[i] = 0x31 }
                authPayload[0x1E] = 0x01
                authPayload[0x2D] = 0x01
                let nome = Array("Domus".utf8)
                for (i, b) in nome.enumerated() { authPayload[0x30 + i] = b }

                guard let (err1, dec1) = inviaERicevi(
                    fd: fd,
                    ip: ip,
                    devType: 0x60C8,
                    cmd: 0x65,
                    payload: authPayload,
                    chiave: chiaveIniziale,
                    devId: Data([0, 0, 0, 0]),
                    mac: mac,
                    contatore: 1
                ), err1 == 0, dec1.count >= 0x14 else {
                    cont.resume(returning: nil)
                    return
                }

                let devId = dec1.subdata(in: 0x00..<0x04)
                let chiaveSessione = dec1.subdata(in: 0x04..<0x14)

                // 2. Comando LB1 JSON (cmd 0x6A, flag 1 = leggi, flag 2 = scrivi)
                let lungTotale = UInt16(12 + json.count)
                let lungJson = UInt16(json.count)
                var blocco = Data(count: 14 + json.count)
                blocco[0] = UInt8(lungTotale & 0xFF)
                blocco[1] = UInt8((lungTotale >> 8) & 0xFF)
                blocco[2] = 0xA5; blocco[3] = 0xA5; blocco[4] = 0x5A; blocco[5] = 0x5A
                blocco[8] = flag
                blocco[9] = 0x0B
                blocco[10] = UInt8(lungJson & 0xFF)
                blocco[11] = UInt8((lungJson >> 8) & 0xFF)
                blocco.replaceSubrange(14..<(14 + json.count), with: json)

                var lcs = 0xBEAF
                for i in 2..<blocco.count { lcs = (lcs + Int(blocco[i])) & 0xFFFF }
                blocco[6] = UInt8(lcs & 0xFF)
                blocco[7] = UInt8((lcs >> 8) & 0xFF)

                guard let (err2, dec2) = inviaERicevi(
                    fd: fd,
                    ip: ip,
                    devType: 0x60C8,
                    cmd: 0x6A,
                    payload: blocco,
                    chiave: chiaveSessione,
                    devId: devId,
                    mac: mac,
                    contatore: 2
                ), err2 == 0, dec2.count >= 14 else {
                    cont.resume(returning: nil)
                    return
                }

                let jLen = Int(UInt16(dec2[10]) | (UInt16(dec2[11]) << 8))
                guard jLen >= 0, 14 + jLen <= dec2.count else {
                    cont.resume(returning: Data())
                    return
                }
                cont.resume(returning: dec2.subdata(in: 14..<(14 + jLen)))
            }
        }
    }

    private static func inviaERicevi(
        fd: Int32,
        ip: String,
        devType: UInt16,
        cmd: UInt16,
        payload: Data,
        chiave: Data,
        devId: Data,
        mac: [UInt8],
        contatore: UInt16
    ) -> (Int16, Data)? {
        var padded = payload
        let resto = padded.count % 16
        if resto != 0 {
            padded.append(Data(repeating: 0, count: 16 - resto))
        }
        var pcs = 0xBEAF
        for b in padded { pcs = (pcs + Int(b)) & 0xFFFF }

        guard let cifrato = CrittografiaTuya.aesCBC(padded, chiave: chiave, iv: iv, cifra: true) else { return nil }

        var pkt = Data(count: 0x38 + cifrato.count)
        pkt[0x00] = 0x5A; pkt[0x01] = 0xA5; pkt[0x02] = 0xAA; pkt[0x03] = 0x55
        pkt[0x04] = 0x5A; pkt[0x05] = 0xA5; pkt[0x06] = 0xAA; pkt[0x07] = 0x55
        pkt[0x24] = UInt8(devType & 0xFF); pkt[0x25] = UInt8((devType >> 8) & 0xFF)
        pkt[0x26] = UInt8(cmd & 0xFF); pkt[0x27] = UInt8((cmd >> 8) & 0xFF)
        pkt[0x28] = UInt8(contatore & 0xFF); pkt[0x29] = UInt8((contatore >> 8) & 0xFF)
        for i in 0..<6 { pkt[0x2A + i] = mac[5 - i] }
        for i in 0..<4 { pkt[0x30 + i] = devId[devId.startIndex + i] }
        pkt[0x34] = UInt8(pcs & 0xFF); pkt[0x35] = UInt8((pcs >> 8) & 0xFF)
        pkt.replaceSubrange(0x38..<(0x38 + cifrato.count), with: cifrato)

        var cs = 0xBEAF
        for b in pkt { cs = (cs + Int(b)) & 0xFFFF }
        pkt[0x20] = UInt8(cs & 0xFF); pkt[0x21] = UInt8((cs >> 8) & 0xFF)

        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = portaControllo.bigEndian
        guard ip.withCString({ inet_pton(AF_INET, $0, &dest.sin_addr) }) == 1 else { return nil }

        let inviati = pkt.withUnsafeBytes { pPtr in
            withUnsafePointer(to: &dest) { dPtr in
                dPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, pPtr.baseAddress, pPtr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard inviati > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: 1024)
        let letti = recv(fd, &buf, buf.count, 0)
        guard letti >= 0x38 else { return nil }
        let err = Int16(bitPattern: UInt16(buf[0x22]) | (UInt16(buf[0x23]) << 8))
        if err != 0 || letti == 0x38 { return (err, Data()) }
        let encResp = Data(buf[0x38..<letti])
        guard let dec = CrittografiaTuya.aesCBC(encResp, chiave: chiave, iv: iv, cifra: false) else { return nil }
        return (err, dec)
    }

    private static func costruisciDiscovery(ipLocale: String, portaLocale: UInt16) -> Data {
        var pkt = Data(count: 48)
        let parti = ipLocale.split(separator: ".").compactMap { UInt8($0) }
        if parti.count == 4 {
            pkt[0x18] = parti[0]; pkt[0x19] = parti[1]; pkt[0x1A] = parti[2]; pkt[0x1B] = parti[3]
        }
        pkt[0x1C] = UInt8(portaLocale & 0xFF)
        pkt[0x1D] = UInt8((portaLocale >> 8) & 0xFF)
        pkt[0x26] = 6
        var cs = 0xBEAF
        for b in pkt { cs = (cs + Int(b)) & 0xFFFF }
        pkt[0x20] = UInt8(cs & 0xFF)
        pkt[0x21] = UInt8((cs >> 8) & 0xFF)
        return pkt
    }

    private static func byteMAC(da stringa: String?) -> [UInt8] {
        guard let s = stringa else { return [0, 0, 0, 0, 0, 0] }
        let hex = s.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard hex.count == 12 else { return [0, 0, 0, 0, 0, 0] }
        var out: [UInt8] = []
        var idx = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(idx, offsetBy: 2)
            out.append(UInt8(hex[idx..<next], radix: 16) ?? 0)
            idx = next
        }
        return out
    }
}
