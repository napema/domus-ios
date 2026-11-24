import Darwin
import Foundation
import Network

/// Risposta grezza letta da un controller Magic Home / Zengge sulla porta TCP 5577 (`0x81 0x8A 0x8B 0x96`).
struct StatoMagicHome: Sendable, Hashable {
    let modello: UInt8
    let versione: UInt8
    let accesa: Bool
    let modalita: UInt8
    let velocita: UInt8
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let ww: UInt8
    let cw: UInt8

    var varianteRilevata: VarianteMagicHome {
        if modello == 0x41 { return .dimmer }
        if modello == 0x35 || (modello == 0x44 && versione >= 7) { return .rgbcct }
        if versione == 0 && modello == 0x04 { return .rgbClassico }
        return .rgbw
    }

    var tipoProbabile: TipoLuce {
        // I controller 0x35 / 0x44 sono quasi sempre lampadine smart; 0x33 / 0x25 / 0x04 / 0x06 strisce LED
        if modello == 0x35 || modello == 0x44 { return .lampadina }
        return .striscia
    }
}

struct ScopertaMagicHome: Sendable, Hashable {
    let ip: String
    let mac: String?
    let codiceModello: String?
    let stato: StatoMagicHome?
}

/// Motore nativo per lampadine e strisce LED Magic Home (魔法家 / Zengge / Flux LED).
/// Usa TCP porta 5577 per comandi istantanei e combina broadcast UDP 48899 + scansione sottorete TCP 5577
/// così funziona anche con firma gratuita SideStore senza entitlement Multicast Apple.
enum ProtocolloMagicHome {
    static let portaControllo: UInt16 = 5577
    static let portaScopertaUDP: UInt16 = 48899

    static func checksum(_ byte: [UInt8]) -> UInt8 {
        var somma = 0
        for b in byte { somma = (somma + Int(b)) & 0xFF }
        return UInt8(somma)
    }

    static func pacchettoConChecksum(_ corpo: [UInt8]) -> Data {
        var p = corpo
        p.append(checksum(corpo))
        return Data(p)
    }

    /// Accende (`0x71 0x23 0x0F 0xA3`) o spegne (`0x71 0x24 0x0F 0xA4`) il dispositivo.
    static func impostaAccensione(ip: String, porta: Int = 5577, accesa: Bool) async -> Bool {
        let cmd: [UInt8] = [0x71, accesa ? 0x23 : 0x24, 0x0F]
        return await inviaPacchetto(ip: ip, porta: porta, dati: pacchettoConChecksum(cmd), attendiRisposta: 0) != nil
    }

    /// Imposta un colore RGB pieno (0...255) secondo la variante hardware del controller.
    static func impostaColore(
        ip: String,
        porta: Int = 5577,
        r: UInt8,
        g: UInt8,
        b: UInt8,
        variante: VarianteMagicHome,
        assicuraAccesa: Bool = true
    ) async -> Bool {
        if assicuraAccesa {
            _ = await impostaAccensione(ip: ip, porta: porta, accesa: true)
        }
        let corpo: [UInt8]
        switch variante {
        case .rgbcct:
            corpo = [0x31, r, g, b, 0x00, 0x00, 0xF0, 0x0F]
        case .rgbClassico:
            corpo = [0x31, r, g, b, 0x00, 0x00, 0x0F]
        case .dimmer:
            let m = max(r, g, b)
            corpo = [0x31, m, 0x00, 0x00, 0x00, 0x0F, 0x0F]
        case .rgbw:
            corpo = [0x31, r, g, b, 0x00, 0xF0, 0x0F]
        }
        return await inviaPacchetto(ip: ip, porta: porta, dati: pacchettoConChecksum(corpo), attendiRisposta: 0) != nil
    }

    /// Imposta la modalità Bianco Caldo/Freddo (2700K...6500K) adattandosi automaticamente a lampadine CCT, RGBW o strisce RGB.
    static func impostaBianco(
        ip: String,
        porta: Int = 5577,
        luminosita: Double,
        temperatura: Double,
        variante: VarianteMagicHome,
        assicuraAccesa: Bool = true
    ) async -> Bool {
        if assicuraAccesa {
            _ = await impostaAccensione(ip: ip, porta: porta, accesa: true)
        }
        let lum = min(1.0, max(0.01, luminosita))
        let temp = min(1.0, max(0.0, temperatura))
        let corpo: [UInt8]

        switch variante {
        case .rgbcct:
            let ww = UInt8(min(255, max(0, Int(((1.0 - temp) * lum * 255.0).rounded()))))
            let cw = UInt8(min(255, max(0, Int((temp * lum * 255.0).rounded()))))
            corpo = [0x31, 0x00, 0x00, 0x00, ww, cw, 0x0F, 0x0F]
        case .rgbw:
            if temp <= 0.25 {
                let ww = UInt8(min(255, max(1, Int((lum * 255.0).rounded()))))
                corpo = [0x31, 0x00, 0x00, 0x00, ww, 0x0F, 0x0F]
            } else {
                let (r, g, b) = kelvinVersoRGB(temperatura: temp, luminosita: lum)
                corpo = [0x31, r, g, b, 0x00, 0xF0, 0x0F]
            }
        case .rgbClassico:
            let (r, g, b) = kelvinVersoRGB(temperatura: temp, luminosita: lum)
            corpo = [0x31, r, g, b, 0x00, 0x00, 0x0F]
        case .dimmer:
            let w = UInt8(min(255, max(1, Int((lum * 255.0).rounded()))))
            corpo = [0x31, w, 0x00, 0x00, 0x00, 0x0F, 0x0F]
        }
        return await inviaPacchetto(ip: ip, porta: porta, dati: pacchettoConChecksum(corpo), attendiRisposta: 0) != nil
    }

    /// Attiva uno degli effetti dinamici integrati nel firmware Magic Home (`0x61 [codice] [ritardo 1..31] 0x0F`).
    static func impostaEffetto(
        ip: String,
        porta: Int = 5577,
        codice: Int,
        velocita: Double,
        assicuraAccesa: Bool = true
    ) async -> Bool {
        if assicuraAccesa {
            _ = await impostaAccensione(ip: ip, porta: porta, accesa: true)
        }
        let v = min(1.0, max(0.0, velocita))
        let ritardo = UInt8(max(1, min(31, Int((31.0 - v * 30.0).rounded()))))
        let corpo: [UInt8] = [0x61, UInt8(clamping: codice), ritardo, 0x0F]
        return await inviaPacchetto(ip: ip, porta: porta, dati: pacchettoConChecksum(corpo), attendiRisposta: 0) != nil
    }

    /// Legge lo stato reale a 14 byte (`0x81 0x8A 0x8B 0x96`) dal controller Magic Home.
    static func leggiStato(ip: String, porta: Int = 5577, timeout: TimeInterval = 1.3) async -> StatoMagicHome? {
        let richiesta = Data([0x81, 0x8A, 0x8B, 0x96])
        guard let risposta = await inviaPacchetto(ip: ip, porta: porta, dati: richiesta, attendiRisposta: 14, timeout: timeout),
              risposta.count >= 14 else {
            return nil
        }
        let b = Array(risposta)
        guard b[0] == 0x81 else { return nil }
        return StatoMagicHome(
            modello: b[1],
            versione: b[10],
            accesa: b[2] == 0x23,
            modalita: b[3],
            velocita: b[5],
            r: b[6],
            g: b[7],
            b: b[8],
            ww: b[9],
            cw: b[11]
        )
    }

    /// Applica l'intero stato di una `Luce` al dispositivo Magic Home.
    static func applica(_ luce: Luce) async -> Bool {
        guard let ip = luce.ip, !ip.isEmpty else { return false }
        if !luce.accensione {
            return await impostaAccensione(ip: ip, porta: luce.porta, accesa: false)
        }
        switch luce.modo {
        case .bianco:
            return await impostaBianco(
                ip: ip,
                porta: luce.porta,
                luminosita: luce.luminosita,
                temperatura: luce.temperatura,
                variante: luce.varianteMagic
            )
        case .colore:
            let c = luce.rgb
            return await impostaColore(
                ip: ip,
                porta: luce.porta,
                r: c.r,
                g: c.g,
                b: c.b,
                variante: luce.varianteMagic
            )
        case .effetto:
            return await impostaEffetto(
                ip: ip,
                porta: luce.porta,
                codice: luce.effetto,
                velocita: luce.velocitaEffetto
            )
        }
    }

    /// Scoperta broadcast UDP 48899 (`HF-A11ASSISTHREAD`), usata in parallelo alla scansione TCP 5577.
    static func scopriViaUDP(indirizzoBroadcast: String = "255.255.255.255", attesa: TimeInterval = 1.1) async -> [ScopertaMagicHome] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var risultati: [String: ScopertaMagicHome] = [:]
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else {
                    cont.resume(returning: [])
                    return
                }
                defer { close(fd) }

                var abilita: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &abilita, socklen_t(MemoryLayout<Int32>.size))
                var tv = timeval(tv_sec: 0, tv_usec: 250_000)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var dest = sockaddr_in()
                dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                dest.sin_family = sa_family_t(AF_INET)
                dest.sin_port = portaScopertaUDP.bigEndian
                _ = indirizzoBroadcast.withCString { inet_pton(AF_INET, $0, &dest.sin_addr) }

                let messaggio = Array("HF-A11ASSISTHREAD".utf8)
                for _ in 0..<2 {
                    _ = messaggio.withUnsafeBytes { ptr in
                        withUnsafePointer(to: &dest) { dPtr in
                            dPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                                sendto(fd, ptr.baseAddress, ptr.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                }

                let scadenza = Date().addingTimeInterval(attesa)
                var buffer = [UInt8](repeating: 0, count: 256)
                while Date() < scadenza {
                    var mittente = sockaddr_in()
                    var lun = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let letti = buffer.withUnsafeMutableBytes { bPtr in
                        withUnsafeMutablePointer(to: &mittente) { mPtr in
                            mPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                                recvfrom(fd, bPtr.baseAddress, bPtr.count, 0, saPtr, &lun)
                            }
                        }
                    }
                    if letti > 0, let testo = String(bytes: buffer[0..<letti], encoding: .utf8) {
                        // Risposta tipica: "192.168.1.54,ACCF23445566,AK001-ZJ2145"
                        let parti = testo.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
                        if let ip = parti.first, ip.contains("."), ip != "HF-A11ASSISTHREAD" {
                            let mac = parti.count > 1 ? parti[1] : nil
                            let mod = parti.count > 2 ? parti[2] : nil
                            risultati[ip] = ScopertaMagicHome(ip: ip, mac: mac, codiceModello: mod, stato: nil)
                        }
                    }
                }
                cont.resume(returning: Array(risultati.values))
            }
        }
    }

    private static func kelvinVersoRGB(temperatura: Double, luminosita: Double) -> (UInt8, UInt8, UInt8) {
        let t = min(1.0, max(0.0, temperatura))
        let r = (1.0 - t * 0.12) * luminosita
        let g = (0.74 + t * 0.22) * luminosita
        let b = (0.42 + t * 0.58) * luminosita
        return (
            UInt8(min(255, max(0, Int((r * 255.0).rounded())))),
            UInt8(min(255, max(0, Int((g * 255.0).rounded())))),
            UInt8(min(255, max(0, Int((b * 255.0).rounded()))))
        )
    }

    /// Invio TCP singolo veloce con timeout controllato tramite `NWConnection`.
    static func inviaPacchetto(
        ip: String,
        porta: Int,
        dati: Data,
        attendiRisposta: Int,
        timeout: TimeInterval = 1.5
    ) async -> Data? {
        guard let nwPorta = NWEndpoint.Port(rawValue: UInt16(clamping: porta)) else { return nil }
        return await withCheckedContinuation { cont in
            let coda = DispatchQueue(label: "it.domus.magichome.\(UUID().uuidString)")
            let stato = ScatolaCompletamento<Data?>()
            let conn = NWConnection(host: NWEndpoint.Host(ip), port: nwPorta, using: .tcp)

            let chiudi: (Data?) -> Void = { esito in
                guard stato.completaUnaVolta() else { return }
                conn.cancel()
                cont.resume(returning: esito)
            }

            coda.asyncAfter(deadline: .now() + timeout) {
                chiudi(nil)
            }

            conn.stateUpdateHandler = { nuovoStato in
                switch nuovoStato {
                case .ready:
                    conn.send(content: dati, completion: .contentProcessed { errore in
                        if errore != nil {
                            chiudi(nil)
                            return
                        }
                        if attendiRisposta <= 0 {
                            coda.asyncAfter(deadline: .now() + 0.04) {
                                chiudi(Data())
                            }
                        } else {
                            conn.receive(minimumIncompleteLength: attendiRisposta, maximumLength: 64) { ricevuti, _, _, err in
                                if err != nil || ricevuti == nil {
                                    chiudi(nil)
                                } else {
                                    chiudi(ricevuti)
                                }
                            }
                        }
                    })
                case .failed, .cancelled:
                    chiudi(nil)
                default:
                    break
                }
            }
            conn.start(queue: coda)
        }
    }
}

/// Guardia thread-safe per evitare doppie riprese di `CheckedContinuation`.
final class ScatolaCompletamento<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var completato = false

    func completaUnaVolta() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completato { return false }
        completato = true
        return true
    }
}
