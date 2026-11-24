import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class GestoreLuci: ObservableObject {
    static let s = GestoreLuci()

    struct Avviso: Identifiable, Equatable {
        let id = UUID()
        let testo: String
        let errore: Bool
    }

    @Published var luci: [Luce] = []
    @Published var credenzialiTuya: CredenzialiTuya = CredenzialiTuya()
    @Published var scansioneInCorso = false
    @Published var sincronizzazioneTuyaInCorso = false
    @Published var statoScansione: String = ""
    @Published var avviso: Avviso?
    @Published var luceApertaID: String?
    @Published var mostraAggiungi = false

    private var inviiPendenti: [String: Task<Void, Never>] = [:]
    private let inDemo = ProcessInfo.processInfo.environment["DOMUS_DEMO"] != nil

    private init() {
        credenzialiTuya = ArchivioCondiviso.caricaCredenzialiTuya()
        let salvate = ArchivioCondiviso.caricaLuci()
        if salvate.isEmpty && inDemo {
            luci = ArchivioCondiviso.esempi
        } else {
            luci = salvate
        }
    }

    // MARK: - Interrogazioni rapide per la UI

    var stanze: [String] {
        let uniche = Set(luci.map { $0.stanza.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return uniche.sorted()
    }

    var acceseCount: Int {
        luci.filter(\.accensione).count
    }

    var strisce: [Luce] {
        luci.filter { $0.tipo == .striscia }
    }

    func luce(id: String) -> Luce? {
        luci.first { $0.id == id }
    }

    // MARK: - Persistenza e avvisi

    func salva() {
        ArchivioCondiviso.salvaLuci(luci)
    }

    func salvaCredenziali(_ nuove: CredenzialiTuya) {
        credenzialiTuya = nuove
        ArchivioCondiviso.salvaCredenzialiTuya(nuove)
        Task { await ProtocolloTuyaCloud.condiviso.invalidaToken() }
    }

    func mostraAvviso(_ testo: String, errore: Bool = false) {
        let a = Avviso(testo: testo, errore: errore)
        withAnimation(.snappy) { avviso = a }
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            if avviso?.id == a.id {
                withAnimation(.easeOut(duration: 0.25)) { avviso = nil }
            }
        }
    }

    func caricaEsempiDimostrativi() {
        luci = ArchivioCondiviso.esempi
        salva()
        mostraAvviso("Luci dimostrative caricate")
    }

    // MARK: - Controllo singola luce (con anti-rimbalzo per slider fluidi a 60 fps)

    func commuta(_ id: String) {
        guard let idx = luci.firstIndex(where: { $0.id == id }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        luci[idx].accensione.toggle()
        salva()
        pianificaInvio(id: id, immediato: true)
    }

    func aggiorna(_ luceModificata: Luce, immediato: Bool = false) {
        guard let idx = luci.firstIndex(where: { $0.id == luceModificata.id }) else { return }
        luci[idx] = luceModificata
        ArchivioCondiviso.salvaLuci(luci, aggiornaWidget: immediato)
        pianificaInvio(id: luceModificata.id, immediato: immediato)
    }

    func elimina(_ id: String) {
        inviiPendenti[id]?.cancel()
        inviiPendenti[id] = nil
        luci.removeAll { $0.id == id }
        if luceApertaID == id { luceApertaID = nil }
        salva()
    }

    func aggiungiOModifica(_ nuova: Luce) {
        if let idx = luci.firstIndex(where: { $0.id == nuova.id }) {
            luci[idx] = nuova
        } else {
            luci.append(nuova)
        }
        salva()
    }

    private func pianificaInvio(id: String, immediato: Bool) {
        inviiPendenti[id]?.cancel()
        guard !inDemo else { return }
        inviiPendenti[id] = Task { [weak self] in
            if !immediato {
                try? await Task.sleep(for: .milliseconds(95))
            }
            guard !Task.isCancelled, let self, let snapshot = self.luce(id: id) else { return }
            let cred = self.credenzialiTuya
            let esito = await ControlloRapido.applica(snapshot, credenzialiTuya: cred)
            guard !Task.isCancelled else { return }
            if let i = self.luci.firstIndex(where: { $0.id == id }) {
                self.luci[i].online = esito.riuscito
                self.luci[i].viaLocale = esito.viaLocale
                if let ver = esito.versioneTuya {
                    self.luci[i].versioneProtocollo = ver
                }
                ArchivioCondiviso.salvaLuci(self.luci)
            }
        }
    }

    // MARK: - Azioni di gruppo / stanza / strisce sincronizzate

    func impostaTutte(accese: Bool, inStanza stanza: String? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var bersagli: [String] = []
        for idx in luci.indices {
            if let stanza, luci[idx].stanza != stanza { continue }
            luci[idx].accensione = accese
            bersagli.append(luci[idx].id)
        }
        salva()
        for id in bersagli {
            pianificaInvio(id: id, immediato: true)
        }
    }

    /// Applica un'atmosfera unificata contemporaneamente a luci Tuya e Magic Home.
    func applicaScena(modo: ModoLuce, tonalita: Double = 0, saturazione: Double = 0.85, temperatura: Double = 0.3, luminosita: Double = 0.85, codiceEffetto: Int = 0x25, soloStrisce: Bool = false, stanza: String? = nil) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var bersagli: [String] = []
        for idx in luci.indices {
            if soloStrisce && luci[idx].tipo != .striscia { continue }
            if let stanza, luci[idx].stanza != stanza { continue }
            luci[idx].accensione = true
            luci[idx].modo = modo
            luci[idx].luminosita = luminosita
            switch modo {
            case .bianco:
                luci[idx].temperatura = temperatura
            case .colore:
                luci[idx].tonalita = tonalita
                luci[idx].saturazione = saturazione
            case .effetto:
                luci[idx].effetto = codiceEffetto
                luci[idx].tonalita = tonalita
                luci[idx].saturazione = 0.9
            }
            bersagli.append(luci[idx].id)
        }
        salva()
        for id in bersagli {
            pianificaInvio(id: id, immediato: true)
        }
    }

    // MARK: - Aggiornamento stati reali all'apertura dell'app

    func aggiornaStatiDaRete() async {
        guard !inDemo, !luci.isEmpty else { return }
        let cred = credenzialiTuya
        let copia = luci

        await withTaskGroup(of: (String, StatoMagicHome?, Luce?).self) { gruppo in
            for l in copia {
                gruppo.addTask {
                    switch l.marca {
                    case .magicHome:
                        guard let ip = l.ip, !ip.isEmpty else { return (l.id, nil, nil) }
                        let stato = await ProtocolloMagicHome.leggiStato(ip: ip, porta: l.porta)
                        return (l.id, stato, nil)
                    case .tuya:
                        let aggCloud = await ProtocolloTuyaCloud.condiviso.aggiornaStato(di: l, credenziali: cred)
                        return (l.id, nil, aggCloud)
                    }
                }
            }

            for await (id, statoMH, luceTuya) in gruppo {
                guard let idx = luci.firstIndex(where: { $0.id == id }) else { continue }
                if let statoMH {
                    luci[idx].online = true
                    luci[idx].viaLocale = true
                    luci[idx].accensione = statoMH.accesa
                    luci[idx].varianteMagic = statoMH.varianteRilevata
                    if statoMH.modalita >= 0x25 && statoMH.modalita <= 0x38 {
                        luci[idx].modo = .effetto
                        luci[idx].effetto = Int(statoMH.modalita)
                    } else if statoMH.ww > 0 || statoMH.cw > 0 {
                        luci[idx].modo = .bianco
                        let maxW = Double(max(statoMH.ww, statoMH.cw)) / 255.0
                        if maxW > 0.02 { luci[idx].luminosita = maxW }
                        let tot = Double(statoMH.ww) + Double(statoMH.cw)
                        if tot > 0 { luci[idx].temperatura = Double(statoMH.cw) / tot }
                    } else if statoMH.r > 0 || statoMH.g > 0 || statoMH.b > 0 {
                        luci[idx].modo = .colore
                        luci[idx].impostaDaRGB(r: statoMH.r, g: statoMH.g, b: statoMH.b)
                    }
                } else if let luceTuya {
                    luci[idx].accensione = luceTuya.accensione
                    luci[idx].luminosita = luceTuya.luminosita
                    luci[idx].temperatura = luceTuya.temperatura
                    luci[idx].tonalita = luceTuya.tonalita
                    luci[idx].saturazione = luceTuya.saturazione
                    luci[idx].modo = luceTuya.modo
                    luci[idx].online = luceTuya.online
                    luci[idx].schemaTuya = luceTuya.schemaTuya
                    luci[idx].codiceSwitchTuya = luceTuya.codiceSwitchTuya
                }
            }
        }
        salva()
    }

    // MARK: - Scansione automatica Wi-Fi (Magic Home 5577/48899 + Tuya LAN 6668/6666/6667)

    func scansionaReteWiFi() async -> Int {
        guard !scansioneInCorso else { return 0 }
        scansioneInCorso = true
        defer {
            scansioneInCorso = false
            statoScansione = ""
        }

        let wifi = ReteLocale.infoWiFi()
        statoScansione = wifi != nil ? "Scansione Wi-Fi \(wifi!.prefissoSottorete).x in corso…" : "Ricerca dispositivi sulla rete locale…"

        async let udpMagic = ProtocolloMagicHome.scopriViaUDP(indirizzoBroadcast: wifi?.broadcast ?? "255.255.255.255")
        async let tcpMagic = Self.scansionaSeWiFi(wifi, porta: 5577)
        async let udpTuya = ProtocolloTuyaLocale.ascoltaAnnunciUDP()
        async let tcpTuya = Self.scansionaSeWiFi(wifi, porta: 6668)

        let (risUDPMagic, ipTCPMagic, annunciTuya, ipTCPTuya) = await (udpMagic, tcpMagic, udpTuya, tcpTuya)

        var mappaMagic: [String: ScopertaMagicHome] = [:]
        for s in risUDPMagic { mappaMagic[s.ip] = s }
        for ip in ipTCPMagic where mappaMagic[ip] == nil {
            mappaMagic[ip] = ScopertaMagicHome(ip: ip, mac: nil, codiceModello: nil, stato: nil)
        }

        var aggiunteOAggiornate = 0

        // 1. Integra ogni controller Magic Home trovato
        statoScansione = "Lettura stato controller Magic Home…"
        for (ip, scoperta) in mappaMagic {
            let stato = await ProtocolloMagicHome.leggiStato(ip: ip, porta: 5577)
            // Verifica che risponda davvero al protocollo Magic Home (o provenga da UDP 48899)
            guard stato != nil || scoperta.mac != nil else { continue }

            let idUnivoco = scoperta.mac.map { "mh-\($0.lowercased())" } ?? "mh-\(ip.replacingOccurrences(of: ".", with: "-"))"
            if let idx = luci.firstIndex(where: { $0.id == idUnivoco || ($0.marca == .magicHome && $0.ip == ip) }) {
                luci[idx].ip = ip
                if let m = scoperta.mac { luci[idx].mac = m }
                luci[idx].online = true
                luci[idx].viaLocale = true
                if let stato {
                    luci[idx].accensione = stato.accesa
                    luci[idx].varianteMagic = stato.varianteRilevata
                }
                aggiunteOAggiornate += 1
            } else {
                let tipo = stato?.tipoProbabile ?? .striscia
                let suffisso = ip.split(separator: ".").last.map(String.init) ?? ""
                var nuova = Luce(
                    id: idUnivoco,
                    nome: tipo == .striscia ? "Striscia Magic \(suffisso)" : "Lampadina Magic \(suffisso)",
                    stanza: "Casa",
                    marca: .magicHome,
                    tipo: tipo,
                    accensione: stato?.accesa ?? false,
                    ip: ip,
                    porta: 5577,
                    mac: scoperta.mac,
                    varianteMagic: stato?.varianteRilevata ?? .rgbw,
                    online: true,
                    viaLocale: true
                )
                if let stato, (stato.r > 0 || stato.g > 0 || stato.b > 0) {
                    nuova.modo = .colore
                    nuova.impostaDaRGB(r: stato.r, g: stato.g, b: stato.b)
                }
                luci.append(nuova)
                aggiunteOAggiornate += 1
            }
        }

        // 2. Associa gli IP locali e la versione protocollo (3.3 / 3.4 / 3.5) alle luci Tuya
        for annuncio in annunciTuya {
            if let idx = luci.firstIndex(where: { $0.tuyaId == annuncio.gwId }) {
                luci[idx].ip = annuncio.ip
                luci[idx].versioneProtocollo = annuncio.versione
                luci[idx].viaLocale = true
                luci[idx].online = true
                aggiunteOAggiornate += 1
            }
        }

        let ipTuyaSenzaAssociazione = ipTCPTuya.filter { ip in !luci.contains(where: { $0.ip == ip }) }
        if !ipTuyaSenzaAssociazione.isEmpty {
            statoScansione = "Abbinamento chiavi locali Tuya sulla porta 6668…"
            for idx in luci.indices where luci[idx].marca == .tuya && (luci[idx].ip == nil || luci[idx].ip?.isEmpty == true) {
                guard let devId = luci[idx].tuyaId, let key = luci[idx].localKey, key.utf8.count == 16 else { continue }
                for ip in ipTuyaSenzaAssociazione {
                    if let ver = await ProtocolloTuyaLocale.verificaCorrispondenza(ip: ip, devId: devId, localKey: key) {
                        luci[idx].ip = ip
                        luci[idx].versioneProtocollo = ver
                        luci[idx].viaLocale = true
                        luci[idx].online = true
                        aggiunteOAggiornate += 1
                        break
                    }
                }
            }
        }

        salva()
        return aggiunteOAggiornate
    }

    private nonisolated static func scansionaSeWiFi(_ wifi: InfoReteWiFi?, porta: UInt16) async -> [String] {
        guard let w = wifi else { return [] }
        return await ReteLocale.scansionaPorta(prefisso: w.prefissoSottorete, porta: porta, escludendo: w.ipLocale)
    }

    // MARK: - Sincronizzazione Cloud Tuya + abbinamento automatico LAN

    func sincronizzaTuyaCloud() async {
        guard credenzialiTuya.configurate else {
            mostraAvviso("Inserisci prima Access ID e Access Secret Tuya", errore: true)
            return
        }
        sincronizzazioneTuyaInCorso = true
        defer { sincronizzazioneTuyaInCorso = false }

        do {
            let importate = try await ProtocolloTuyaCloud.condiviso.importaLuci(credenziali: credenzialiTuya)
            if importate.isEmpty {
                mostraAvviso("Nessuna lampadina o striscia trovata sull'account Tuya collegato", errore: true)
                return
            }
            for t in importate {
                if let idx = luci.firstIndex(where: { $0.tuyaId == t.tuyaId || $0.id == t.id }) {
                    // Preserva stanza personalizzata, nome modificato e IP locale già scoperto
                    luci[idx].localKey = t.localKey ?? luci[idx].localKey
                    luci[idx].accensione = t.accensione
                    luci[idx].luminosita = t.luminosita
                    luci[idx].temperatura = t.temperatura
                    luci[idx].tonalita = t.tonalita
                    luci[idx].saturazione = t.saturazione
                    luci[idx].modo = t.modo
                    luci[idx].schemaTuya = t.schemaTuya
                    luci[idx].codiceSwitchTuya = t.codiceSwitchTuya
                    luci[idx].online = t.online
                } else {
                    luci.append(t)
                }
            }
            salva()
            mostraAvviso("Importate \(importate.count) luci Tuya · cerco gli IP locali…")
            _ = await scansionaReteWiFi()
        } catch {
            mostraAvviso(error.localizedDescription, errore: true)
        }
    }

    // MARK: - Import / Export JSON (compatibile anche con output TinyTuya `devices.json`)

    func esportaJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(luci), let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }

    func importaDaJSON(_ testo: String) -> Int {
        guard let dati = testo.data(using: .utf8) else { return 0 }
        if let dirette = try? JSONDecoder().decode([Luce].self, from: dati), !dirette.isEmpty {
            for l in dirette { aggiungiOModifica(l) }
            return dirette.count
        }
        // Supporto diretto anche al formato `devices.json` di TinyTuya (`[{"name":...,"id":...,"key":...,"ip":...,"version":...}]`)
        guard let lista = try? JSONSerialization.jsonObject(with: dati) as? [[String: Any]] else { return 0 }
        var cont = 0
        for voce in lista {
            guard let devId = (voce["id"] as? String) ?? (voce["gwId"] as? String), !devId.isEmpty else { continue }
            let nome = (voce["name"] as? String) ?? "Luce Tuya"
            let key = (voce["key"] as? String) ?? (voce["local_key"] as? String)
            let ip = voce["ip"] as? String
            let ver = (voce["version"] as? String) ?? "3.3"
            let cat = (voce["category"] as? String ?? "").lowercased()
            let tipo: TipoLuce = (cat == "dd" || cat == "dc" || nome.lowercased().contains("strip") || nome.lowercased().contains("striscia") || nome.lowercased().contains("led")) ? .striscia : .lampadina
            let nuova = Luce(
                id: "tuya-\(devId)",
                nome: nome,
                stanza: "Casa",
                marca: .tuya,
                tipo: tipo,
                ip: (ip?.isEmpty == false) ? ip : nil,
                porta: 6668,
                tuyaId: devId,
                localKey: key,
                versioneProtocollo: ver,
                viaLocale: ip?.isEmpty == false
            )
            aggiungiOModifica(nuova)
            cont += 1
        }
        return cont
    }
}
