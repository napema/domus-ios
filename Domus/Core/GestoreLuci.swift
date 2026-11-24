import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

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
    @Published var coloriSalvati: [ColoreSalvato] = []
    @Published var routineSveglia: RoutineSveglia = RoutineSveglia()
    @Published var crescendoInCorso = false
    @Published var progressoCrescendo: String = ""
    @Published var scansioneInCorso = false
    @Published var sincronizzazioneTuyaInCorso = false
    @Published var statoScansione: String = ""
    @Published var avviso: Avviso?
    @Published var luceApertaID: String?
    @Published var mostraAggiungi = false

    private var attesaDebounce: [String: Task<Void, Never>] = [:]
    private var invioInCorso: Set<String> = []
    private var pendenteDopoInvio: Set<String> = []
    private var taskCrescendo: Task<Void, Never>?
    private var ultimoGiornoSvegliaAuto: String = ""
    private var ultimoRecuperoTuya: Date = .distantPast
    private let inDemo = ProcessInfo.processInfo.environment["DOMUS_DEMO"] != nil

    private init() {
        credenzialiTuya = ArchivioCondiviso.caricaCredenzialiTuya()
        coloriSalvati = ArchivioCondiviso.caricaColoriSalvati()
        routineSveglia = ArchivioCondiviso.caricaRoutineSveglia()
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

    // MARK: - Colori personalizzati salvati

    func salvaColoreCorrente(tonalita: Double, saturazione: Double, luminosita: Double = 1.0) {
        let giaPresente = coloriSalvati.contains {
            abs($0.tonalita - tonalita) < 0.015 &&
            abs($0.saturazione - saturazione) < 0.04 &&
            abs($0.luminosita - luminosita) < 0.05
        }
        guard !giaPresente else {
            mostraAvviso("Colore già salvato")
            return
        }
        let nuovo = ColoreSalvato(tonalita: tonalita, saturazione: saturazione, luminosita: luminosita)
        coloriSalvati.append(nuovo)
        ArchivioCondiviso.salvaColoriSalvati(coloriSalvati)
        mostraAvviso("Colore memorizzato")
    }

    func eliminaColoreSalvato(id: String) {
        coloriSalvati.removeAll { $0.id == id }
        ArchivioCondiviso.salvaColoriSalvati(coloriSalvati)
    }

    // MARK: - Routine Sveglia progressiva

    func salvaRoutineSveglia(_ nuova: RoutineSveglia) {
        routineSveglia = nuova
        ArchivioCondiviso.salvaRoutineSveglia(nuova)
        Task { await MotoreSveglia.pianificaNotifica(nuova) }
    }

    func controllaSvegliaProgrammata() {
        guard routineSveglia.attiva, !crescendoInCorso else { return }
        let cal = Calendar.current
        let adesso = Date()
        guard let target = cal.date(bySettingHour: routineSveglia.ora, minute: routineSveglia.minuto, second: 0, of: adesso) else {
            return
        }
        let inizio = target.addingTimeInterval(-Double(routineSveglia.minutiPrima) * 60.0)
        let fine = target.addingTimeInterval(90)
        guard adesso >= inizio && adesso <= fine else { return }

        let comps = cal.dateComponents([.year, .month, .day], from: adesso)
        let chiave = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)-\(routineSveglia.ora):\(routineSveglia.minuto)"
        guard ultimoGiornoSvegliaAuto != chiave else { return }
        ultimoGiornoSvegliaAuto = chiave
        avviaCrescendoSveglia(rapidoDemo: false)
    }

    func avviaCrescendoSveglia(rapidoDemo: Bool = false) {
        taskCrescendo?.cancel()
        guard !luci.isEmpty else {
            mostraAvviso("Nessuna luce configurata per la routine", errore: true)
            return
        }

        let routine = routineSveglia
        crescendoInCorso = true
        progressoCrescendo = rapidoDemo ? "Test rapido avviato (10%)…" : "Crescendo avviato (10%)…"

        taskCrescendo = Task { [weak self] in
            guard let self else { return }
            let target80 = max(0.20, min(1.0, routine.livelloSveglia))
            let target100 = max(target80, min(1.0, routine.livelloDopoMinuto))

            let passi: [(livello: Double, pausaDopo: Double)]
            if rapidoDemo {
                let s1 = 0.10
                let s2 = s1 + (target80 - s1) * 0.40
                let s3 = s1 + (target80 - s1) * 0.72
                passi = [
                    (s1, 2.3),
                    (s2, 2.3),
                    (s3, 2.4),
                    (target80, 3.0),
                    (target100, 0.0),
                ]
            } else {
                let durataRampa = max(30.0, Double(routine.minutiPrima) * 60.0)
                let frazioni = [0.0, 0.22, 0.44, 0.66, 0.84, 1.0]
                let stepPausa = durataRampa / Double(frazioni.count - 1)
                var elenco: [(Double, Double)] = []
                for (i, f) in frazioni.enumerated() {
                    let lvl = 0.10 + (target80 - 0.10) * f
                    let attesa = (i == frazioni.count - 1) ? 60.0 : stepPausa
                    elenco.append((lvl, attesa))
                }
                elenco.append((target100, 0.0))
                passi = elenco
            }

            for passo in passi {
                guard !Task.isCancelled else { break }
                let perc = Int((passo.livello * 100).rounded())
                self.progressoCrescendo = "Luminosità al \(perc)%"
                if routine.soloBianco {
                    self.applicaScena(modo: .bianco, temperatura: routine.temperatura, luminosita: passo.livello)
                } else {
                    self.applicaScena(modo: .colore, tonalita: routine.tonalita, saturazione: routine.saturazione, luminosita: passo.livello)
                }
                if passo.pausaDopo > 0 {
                    try? await Task.sleep(for: .seconds(passo.pausaDopo))
                }
            }

            if !Task.isCancelled {
                self.crescendoInCorso = false
                self.progressoCrescendo = "Completato (\(Int((target100 * 100).rounded()))%)"
            }
        }
    }

    func fermaCrescendoSveglia() {
        taskCrescendo?.cancel()
        taskCrescendo = nil
        crescendoInCorso = false
        progressoCrescendo = "Fermato"
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
        attesaDebounce[id]?.cancel()
        attesaDebounce[id] = nil
        pendenteDopoInvio.remove(id)
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
        guard !inDemo else { return }
        attesaDebounce[id]?.cancel()
        attesaDebounce[id] = nil

        if invioInCorso.contains(id) {
            // Non interrompere la sessione TCP/Cloud in corso: invieremo lo stato più recente appena termina
            pendenteDopoInvio.insert(id)
            return
        }

        if immediato {
            avviaInvioCoalesced(id: id)
        } else {
            attesaDebounce[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(130))
                guard !Task.isCancelled, let self else { return }
                self.attesaDebounce[id] = nil
                self.avviaInvioCoalesced(id: id)
            }
        }
    }

    private func avviaInvioCoalesced(id: String) {
        guard !invioInCorso.contains(id), let snapshot = luce(id: id) else { return }
        invioInCorso.insert(id)

        Task { [weak self] in
            guard let self else { return }
            let cred = self.credenzialiTuya
            var esito = await ControlloRapido.applica(snapshot, credenzialiTuya: cred)
            if snapshot.marca == .tuya && !esito.riuscito {
                await ProtocolloTuyaCloud.condiviso.invalidaToken()
                esito = await ControlloRapido.applica(snapshot, credenzialiTuya: cred)
            }
            if let i = self.luci.firstIndex(where: { $0.id == id }) {
                self.luci[i].online = esito.riuscito
                self.luci[i].viaLocale = esito.viaLocale
                if let ver = esito.versioneTuya {
                    self.luci[i].versioneProtocollo = ver
                }
                ArchivioCondiviso.salvaLuci(self.luci)
            }
            if snapshot.marca == .magicHome && snapshot.varianteMagic == .broadlink && !esito.riuscito {
                self.mostraAvviso("Lampadina Magic Home bloccata: disattiva «Blocca dispositivo» nell'app Magic Home", errore: true)
            }
            if snapshot.marca == .tuya && !esito.viaLocale,
               ReteLocale.infoWiFi() != nil,
               Date().timeIntervalSince(self.ultimoRecuperoTuya) > 120 {
                self.ultimoRecuperoTuya = Date()
                Task { [weak self] in
                    await self?.riallineaIPLocaliTuyaSilenzioso()
                }
            }

            self.invioInCorso.remove(id)
            if self.pendenteDopoInvio.remove(id) != nil {
                self.avviaInvioCoalesced(id: id)
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

        await withTaskGroup(of: (String, StatoMagicHome?, StatoBroadLink?, Luce?).self) { gruppo in
            for l in copia {
                gruppo.addTask {
                    switch l.marca {
                    case .magicHome:
                        guard let ip = l.ip, !ip.isEmpty else { return (l.id, nil, nil, nil) }
                        if l.varianteMagic == .broadlink {
                            let statoBL = await ProtocolloBroadLink.leggiStato(ip: ip, mac: l.mac)
                            return (l.id, nil, statoBL, nil)
                        } else {
                            let stato = await ProtocolloMagicHome.leggiStato(ip: ip, porta: l.porta)
                            return (l.id, stato, nil, nil)
                        }
                    case .tuya:
                        let aggCloud = await ProtocolloTuyaCloud.condiviso.aggiornaStato(di: l, credenziali: cred)
                        return (l.id, nil, nil, aggCloud)
                    }
                }
            }

            for await (id, statoMH, statoBL, luceTuya) in gruppo {
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
                } else if let statoBL {
                    luci[idx].online = true
                    luci[idx].viaLocale = true
                    luci[idx].accensione = statoBL.accesa
                    luci[idx].luminosita = statoBL.luminosita
                    luci[idx].temperatura = statoBL.temperatura
                    luci[idx].tonalita = statoBL.tonalita
                    luci[idx].saturazione = statoBL.saturazione
                    luci[idx].modo = statoBL.modoBianco ? .bianco : .colore
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
        async let broadLinkMagic = Self.scansionaBroadLink(wifi)
        async let udpTuya = ProtocolloTuyaLocale.ascoltaAnnunciUDP()
        async let tcpTuya = Self.scansionaSeWiFi(wifi, porta: 6668)

        let (risUDPMagic, ipTCPMagic, risBroadLink, annunciTuya, ipTCPTuya) = await (udpMagic, tcpMagic, broadLinkMagic, udpTuya, tcpTuya)

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
            // Porta 5577 aperta = controller Magic Home: lo accettiamo anche se lo stato tarda a rispondere
            _ = scoperta.mac

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

        // 1b. Integra lampadine Magic Home / BroadLink (UDP porta 80)
        var bloccataTrovata: String?
        for scoperta in risBroadLink {
            let idUnivoco = "mh-bl-\(scoperta.mac.lowercased())"
            let statoBL = await ProtocolloBroadLink.leggiStato(ip: scoperta.ip, mac: scoperta.mac)
            if scoperta.bloccata && statoBL == nil {
                bloccataTrovata = scoperta.ip
            }
            if let idx = luci.firstIndex(where: { $0.id == idUnivoco || ($0.marca == .magicHome && $0.varianteMagic == .broadlink && $0.ip == scoperta.ip) }) {
                luci[idx].ip = scoperta.ip
                luci[idx].porta = 80
                luci[idx].mac = scoperta.mac
                luci[idx].varianteMagic = .broadlink
                luci[idx].online = true
                luci[idx].viaLocale = true
                if let statoBL {
                    luci[idx].accensione = statoBL.accesa
                    luci[idx].luminosita = statoBL.luminosita
                    luci[idx].temperatura = statoBL.temperatura
                    luci[idx].tonalita = statoBL.tonalita
                    luci[idx].saturazione = statoBL.saturazione
                    luci[idx].modo = statoBL.modoBianco ? .bianco : .colore
                }
                aggiunteOAggiornate += 1
            } else {
                var nuova = Luce(
                    id: idUnivoco,
                    nome: scoperta.nome,
                    stanza: "Casa",
                    marca: .magicHome,
                    tipo: .lampadina,
                    accensione: statoBL?.accesa ?? false,
                    luminosita: statoBL?.luminosita ?? 0.85,
                    temperatura: statoBL?.temperatura ?? 0.35,
                    tonalita: statoBL?.tonalita ?? 0.08,
                    saturazione: statoBL?.saturazione ?? 0.85,
                    modo: (statoBL?.modoBianco ?? true) ? .bianco : .colore,
                    ip: scoperta.ip,
                    porta: 80,
                    mac: scoperta.mac,
                    varianteMagic: .broadlink,
                    online: true,
                    viaLocale: true
                )
                nuova.preferitaWidget = true
                luci.append(nuova)
                aggiunteOAggiornate += 1
            }
        }
        if let ipBloccato = bloccataTrovata {
            mostraAvviso("Trovata lampadina Magic Home (\(ipBloccato)), ma è bloccata: disattiva «Blocca dispositivo» nell'app Magic Home", errore: true)
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

    private nonisolated static func scansionaBroadLink(_ wifi: InfoReteWiFi?) async -> [ScopertaBroadLink] {
        guard let w = wifi else { return [] }
        return await ProtocolloBroadLink.scopri(ipLocale: w.ipLocale, prefisso: w.prefissoSottorete, broadcast: w.broadcast)
    }

    private func riallineaIPLocaliTuyaSilenzioso() async {
        guard let wifi = ReteLocale.infoWiFi() else { return }
        async let annunciTuya = ProtocolloTuyaLocale.ascoltaAnnunciUDP()
        async let ipTCPTuya = Self.scansionaSeWiFi(wifi, porta: 6668)
        let (annunci, ipAperti) = await (annunciTuya, ipTCPTuya)
        var cambiato = false

        for a in annunci {
            if let idx = luci.firstIndex(where: { $0.tuyaId == a.gwId }) {
                if luci[idx].ip != a.ip || luci[idx].versioneProtocollo != a.versione {
                    luci[idx].ip = a.ip
                    luci[idx].versioneProtocollo = a.versione
                    luci[idx].viaLocale = true
                    luci[idx].online = true
                    cambiato = true
                }
            }
        }

        let ipLiberi = ipAperti.filter { ip in !luci.contains(where: { $0.ip == ip }) }
        if !ipLiberi.isEmpty {
            for idx in luci.indices where luci[idx].marca == .tuya {
                guard let devId = luci[idx].tuyaId, let key = luci[idx].localKey, key.utf8.count == 16 else { continue }
                for ip in ipLiberi {
                    if let ver = await ProtocolloTuyaLocale.verificaCorrispondenza(ip: ip, devId: devId, localKey: key) {
                        luci[idx].ip = ip
                        luci[idx].versioneProtocollo = ver
                        luci[idx].viaLocale = true
                        luci[idx].online = true
                        cambiato = true
                        break
                    }
                }
            }
        }
        if cambiato { salva() }
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
        // Formato «setup»: {"tuya":{accessId,accessSecret,regione,uid},"devices":[...]}
        var elenco: [[String: Any]]? = nil
        if let radice = try? JSONSerialization.jsonObject(with: dati) as? [String: Any] {
            if let t = radice["tuya"] as? [String: Any] {
                var c = CredenzialiTuya()
                c.accessId = t["accessId"] as? String ?? ""
                c.accessSecret = t["accessSecret"] as? String ?? ""
                c.uidUtente = t["uid"] as? String ?? ""
                c.regione = RegioneTuya(rawValue: t["regione"] as? String ?? "") ?? .eu
                salvaCredenziali(c)
            }
            elenco = radice["devices"] as? [[String: Any]]
        }
        guard let lista = elenco ?? (try? JSONSerialization.jsonObject(with: dati) as? [[String: Any]]) else { return 0 }
        var cont = 0
        for voce in lista {
            guard let devId = (voce["id"] as? String) ?? (voce["gwId"] as? String), !devId.isEmpty else { continue }
            let nome = (voce["name"] as? String) ?? "Luce Tuya"
            let key = (voce["key"] as? String) ?? (voce["local_key"] as? String)
            let ip = voce["ip"] as? String
            let ver = (voce["version"] as? String) ?? "3.3"
            let cat = (voce["category"] as? String ?? "").lowercased()
            let tipo: TipoLuce = (cat == "dd" || cat == "dc" || nome.lowercased().contains("strip") || nome.lowercased().contains("striscia") || nome.lowercased().contains("led")) ? .striscia : .lampadina
            var nuova = Luce(
                id: "tuya-\(devId)",
                nome: nome,
                stanza: (voce["stanza"] as? String) ?? "Casa",
                marca: .tuya,
                tipo: tipo,
                ip: (ip?.isEmpty == false) ? ip : nil,
                porta: 6668,
                tuyaId: devId,
                localKey: key,
                versioneProtocollo: ver,
                viaLocale: ip?.isEmpty == false
            )
            if let s = voce["schema"] as? String, let sch = SchemaTuya(rawValue: s) { nuova.schemaTuya = sch }
            aggiungiOModifica(nuova)
            cont += 1
        }
        return cont
    }
}

enum MotoreSveglia {
    static let idNotifica = "it.domus.routine.sveglia"

    static func pianificaNotifica(_ routine: RoutineSveglia) async {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: [idNotifica])
        guard routine.attiva else { return }

        let permesso = (try? await centro.requestAuthorization(options: [.alert, .sound])) ?? false
        guard permesso else { return }

        let minutiTotali = ((routine.ora * 60 + routine.minuto) - routine.minutiPrima + 1440) % 1440
        var comps = DateComponents()
        comps.hour = minutiTotali / 60
        comps.minute = minutiTotali % 60

        let contenuto = UNMutableNotificationContent()
        contenuto.title = "Domus · Routine Sveglia"
        contenuto.body = "Tocca per avviare il crescendo di luci verso la sveglia delle \(routine.orarioFormattato)."
        contenuto.sound = .default
        contenuto.userInfo = ["url": "domus://routine-avvia"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let richiesta = UNNotificationRequest(identifier: idNotifica, content: contenuto, trigger: trigger)
        try? await centro.add(richiesta)
    }
}
