import Foundation

enum ErroreTuyaCloud: LocalizedError {
    case credenzialiMancanti
    case rispostaNonValida
    case erroreAPI(codice: Int, messaggio: String)

    var errorDescription: String? {
        switch self {
        case .credenzialiMancanti:
            return "Inserisci Access ID e Access Secret del tuo progetto Tuya Cloud."
        case .rispostaNonValida:
            return "Risposta inattesa dai server Tuya Cloud."
        case let .erroreAPI(codice, messaggio):
            return "Tuya Cloud (\(codice)): \(messaggio)"
        }
    }
}

/// Client nativo per Tuya IoT OpenAPI (v1.0 / v2.0).
/// Serve per due scopi complementari:
/// 1. Importare in 1 tocco tutte le lampadine e strisce LED dell'account Tuya/Smart Life insieme alle `local_key`.
/// 2. Controllare le luci via Cloud quando sei fuori casa (4G/5G) o quando una luce non risponde in LAN.
actor ProtocolloTuyaCloud {
    static let condiviso = ProtocolloTuyaCloud()

    private var tokenAttivo: String?
    private var scadenzaToken: Date = .distantPast
    private var idChiaveToken: String = ""

    private let hashCorpoVuoto = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    func invalidaToken() {
        tokenAttivo = nil
        scadenzaToken = .distantPast
    }

    // MARK: - Autenticazione e firma HMAC-SHA256 (specifica Tuya 2021+)

    private func ottieniToken(credenziali: CredenzialiTuya) async throws -> String {
        guard credenziali.configurate else { throw ErroreTuyaCloud.credenzialiMancanti }
        let chiaveCache = "\(credenziali.regione.rawValue)|\(credenziali.accessId)"
        if let t = tokenAttivo, idChiaveToken == chiaveCache, Date() < scadenzaToken {
            return t
        }

        let dati = try await richiestaFirmata(
            metodo: "GET",
            percorso: "/v1.0/token?grant_type=1",
            corpo: nil,
            token: nil,
            credenziali: credenziali
        )
        guard let json = try? JSONSerialization.jsonObject(with: dati) as? [String: Any] else {
            throw ErroreTuyaCloud.rispostaNonValida
        }
        if let ok = json["success"] as? Bool, !ok {
            let cod = json["code"] as? Int ?? -1
            let msg = json["msg"] as? String ?? "Autenticazione rifiutata"
            throw ErroreTuyaCloud.erroreAPI(codice: cod, messaggio: msg)
        }
        guard let ris = json["result"] as? [String: Any],
              let accessToken = ris["access_token"] as? String else {
            throw ErroreTuyaCloud.rispostaNonValida
        }
        let durata = (ris["expire_time"] as? Double) ?? 7000
        tokenAttivo = accessToken
        idChiaveToken = chiaveCache
        scadenzaToken = Date().addingTimeInterval(max(60, durata - 120))
        return accessToken
    }

    private func ordinaPercorsoEQuery(_ percorsoOriginale: String) -> String {
        guard let comp = URLComponents(string: "https://esempio.it" + percorsoOriginale) else {
            return percorsoOriginale
        }
        guard let items = comp.queryItems, !items.isEmpty else {
            return comp.path
        }
        let ordinati = items.sorted { $0.name < $1.name }
        let query = ordinati.map { voce in
            let v = voce.value ?? ""
            return "\(voce.name)=\(v)"
        }.joined(separator: "&")
        return "\(comp.path)?\(query)"
    }

    private func richiestaFirmata(
        metodo: String,
        percorso: String,
        corpo: Data?,
        token: String?,
        credenziali: CredenzialiTuya
    ) async throws -> Data {
        let clientId = credenziali.accessId.trimmingCharacters(in: .whitespacesAndNewlines)
        let segreto = credenziali.accessSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let percorsoCanonico = ordinaPercorsoEQuery(percorso)
        guard let url = URL(string: credenziali.regione.rawValue + percorsoCanonico) else {
            throw ErroreTuyaCloud.rispostaNonValida
        }

        let t = String(Int64(Date().timeIntervalSince1970 * 1000))
        let hashCorpo = corpo.map { CrittografiaTuya.sha256Esadecimale($0) } ?? hashCorpoVuoto
        let stringToSign = "\(metodo.uppercased())\n\(hashCorpo)\n\n\(percorsoCanonico)"
        let daFirmare = clientId + (token ?? "") + t + stringToSign
        let firma = CrittografiaTuya.hmacSHA256EsadecimaleMaiuscolo(daFirmare, segreto: segreto)

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = metodo.uppercased()
        req.setValue(clientId, forHTTPHeaderField: "client_id")
        req.setValue(firma, forHTTPHeaderField: "sign")
        req.setValue("HMAC-SHA256", forHTTPHeaderField: "sign_method")
        req.setValue(t, forHTTPHeaderField: "t")
        if let token {
            req.setValue(token, forHTTPHeaderField: "access_token")
        }
        if let corpo {
            req.httpBody = corpo
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (dati, _) = try await URLSession.shared.data(for: req)
        return dati
    }

    private func eseguiConRiprova(
        metodo: String,
        percorso: String,
        corpo: Data? = nil,
        credenziali: CredenzialiTuya
    ) async throws -> [String: Any] {
        var token = try await ottieniToken(credenziali: credenziali)
        var dati = try await richiestaFirmata(metodo: metodo, percorso: percorso, corpo: corpo, token: token, credenziali: credenziali)
        var json = (try? JSONSerialization.jsonObject(with: dati) as? [String: Any]) ?? [:]

        // Codice 1010 = token scaduto: rigenera una volta
        if (json["code"] as? Int) == 1010 {
            invalidaToken()
            token = try await ottieniToken(credenziali: credenziali)
            dati = try await richiestaFirmata(metodo: metodo, percorso: percorso, corpo: corpo, token: token, credenziali: credenziali)
            json = (try? JSONSerialization.jsonObject(with: dati) as? [String: Any]) ?? [:]
        }
        return json
    }

    // MARK: - Importazione automatica dispositivi e local_key

    func importaLuci(credenziali: CredenzialiTuya) async throws -> [Luce] {
        var grezzi: [[String: Any]] = []
        var ultimoErrore: ErroreTuyaCloud?

        // 1. Endpoint IoT Core: restituisce tutti gli account collegati via QR ("Link Tuya App Account") con local_key
        let r1 = try await eseguiConRiprova(
            metodo: "GET",
            percorso: "/v1.0/iot-01/associated-users/devices?size=100",
            credenziali: credenziali
        )
        if (r1["success"] as? Bool) == true,
           let ris = r1["result"] as? [String: Any],
           let lista = ris["devices"] as? [[String: Any]] {
            grezzi.append(contentsOf: lista)
        } else if let cod = r1["code"] as? Int, let msg = r1["msg"] as? String {
            ultimoErrore = .erroreAPI(codice: cod, messaggio: msg)
        }

        // 2. Se l'utente ha indicato l'UID dell'account app Tuya/Smart Life o r1 era vuoto
        let uid = credenziali.uidUtente.trimmingCharacters(in: .whitespacesAndNewlines)
        if grezzi.isEmpty, !uid.isEmpty {
            let r2 = try await eseguiConRiprova(
                metodo: "GET",
                percorso: "/v1.0/users/\(uid)/devices",
                credenziali: credenziali
            )
            if (r2["success"] as? Bool) == true, let lista = r2["result"] as? [[String: Any]] {
                grezzi.append(contentsOf: lista)
            } else if let cod = r2["code"] as? Int, let msg = r2["msg"] as? String {
                ultimoErrore = .erroreAPI(codice: cod, messaggio: msg)
            }
        }

        // 3. Fallback v2.0 Cloud Thing Device
        if grezzi.isEmpty {
            let r3 = try await eseguiConRiprova(
                metodo: "GET",
                percorso: "/v2.0/cloud/thing/device?page_size=20",
                credenziali: credenziali
            )
            if (r3["success"] as? Bool) == true, let lista = r3["result"] as? [[String: Any]] {
                for voce in lista {
                    if let id = (voce["id"] as? String) ?? (voce["devId"] as? String) {
                        let dett = try? await eseguiConRiprova(metodo: "GET", percorso: "/v1.0/devices/\(id)", credenziali: credenziali)
                        if let dettRis = dett?["result"] as? [String: Any] {
                            grezzi.append(dettRis)
                        } else {
                            grezzi.append(voce)
                        }
                    }
                }
            }
        }

        if grezzi.isEmpty, let err = ultimoErrore {
            throw err
        }

        var viste: Set<String> = []
        var luci: [Luce] = []

        for disp in grezzi {
            guard let id = disp["id"] as? String, !id.isEmpty, !viste.contains(id) else { continue }
            guard eDispositivoLuce(disp) else { continue }
            viste.insert(id)
            luci.append(convertiDispositivoTuya(disp))
        }
        return luci
    }

    private func eDispositivoLuce(_ d: [String: Any]) -> Bool {
        let categorieLuce: Set<String> = ["dj", "dd", "dc", "xdd", "fwd", "tgq", "tgkg", "tyndj", "fsd", "gyd", "bjd"]
        let cat = (d["category"] as? String ?? "").lowercased()
        if categorieLuce.contains(cat) { return true }

        if let stati = d["status"] as? [[String: Any]] {
            let codici = Set(stati.compactMap { $0["code"] as? String })
            if !codici.intersection(["switch_led", "led_switch", "colour_data_v2", "colour_data", "bright_value_v2", "bright_value"]).isEmpty {
                return true
            }
        }
        let nome = ((d["name"] as? String) ?? (d["customName"] as? String) ?? "").lowercased()
        return nome.contains("led") || nome.contains("strip") || nome.contains("striscia") || nome.contains("luce") || nome.contains("lamp")
    }

    private func convertiDispositivoTuya(_ d: [String: Any]) -> Luce {
        let id = d["id"] as? String ?? UUID().uuidString
        let nome = ((d["customName"] as? String)?.isEmpty == false ? d["customName"] as? String : d["name"] as? String) ?? "Luce Tuya"
        let cat = (d["category"] as? String ?? "").lowercased()
        let nomeBasso = nome.lowercased()
        let tipo: TipoLuce = (cat == "dd" || cat == "dc" || cat == "fwd" || nomeBasso.contains("strip") || nomeBasso.contains("striscia") || nomeBasso.contains("led")) ? .striscia : .lampadina
        let localKey = d["local_key"] as? String ?? d["localKey"] as? String
        let online = (d["online"] as? Bool) ?? (d["isOnline"] as? Bool) ?? true

        var luce = Luce(
            id: "tuya-\(id)",
            nome: nome,
            stanza: "Casa",
            marca: .tuya,
            tipo: tipo,
            porta: 6668,
            tuyaId: id,
            localKey: localKey,
            versioneProtocollo: "3.3",
            online: online
        )

        if let stati = d["status"] as? [[String: Any]] {
            applicaStatiCloud(stati, a: &luce)
        }
        return luce
    }

    func aggiornaStato(di luce: Luce, credenziali: CredenzialiTuya) async -> Luce? {
        guard credenziali.configurate, let tuyaId = luce.tuyaId else { return nil }
        guard let json = try? await eseguiConRiprova(
            metodo: "GET",
            percorso: "/v1.0/iot-03/devices/\(tuyaId)/status",
            credenziali: credenziali
        ) else { return nil }

        var aggiornata = luce
        if let stati = json["result"] as? [[String: Any]] {
            applicaStatiCloud(stati, a: &aggiornata)
            aggiornata.online = true
            return aggiornata
        }
        return nil
    }

    private func applicaStatiCloud(_ stati: [[String: Any]], a luce: inout Luce) {
        let codici = Set(stati.compactMap { $0["code"] as? String })
        if codici.contains("bright_value_v2") || codici.contains("colour_data_v2") || codici.contains("temp_value_v2") {
            luce.schemaTuya = .luceV2
        } else if codici.contains("bright_value") || codici.contains("colour_data") || codici.contains("temp_value") {
            luce.schemaTuya = .luceV1
        } else if codici.contains("switch_1") && !codici.contains("switch_led") {
            luce.schemaTuya = .soloInterruttore
        }

        for voce in stati {
            guard let codice = voce["code"] as? String, let valore = voce["value"] else { continue }
            switch codice {
            case "switch_led", "led_switch", "switch_1":
                luce.codiceSwitchTuya = codice
                if let b = valore as? Bool { luce.accensione = b }
            case "work_mode":
                if let m = valore as? String {
                    switch m {
                    case "colour": luce.modo = .colore
                    case "scene", "music": luce.modo = .effetto
                    default: luce.modo = .bianco
                    }
                }
            case "bright_value_v2":
                if let n = valoreNumerico(valore) {
                    luce.luminosita = min(1, max(0.01, (n - 10.0) / 990.0))
                }
            case "bright_value":
                if let n = valoreNumerico(valore) {
                    luce.luminosita = min(1, max(0.01, (n - 25.0) / 230.0))
                }
            case "temp_value_v2":
                if let n = valoreNumerico(valore) {
                    luce.temperatura = min(1, max(0, n / 1000.0))
                }
            case "temp_value":
                if let n = valoreNumerico(valore) {
                    luce.temperatura = min(1, max(0, n / 255.0))
                }
            case "colour_data_v2":
                if let s = valore as? String,
                   let d = s.data(using: .utf8),
                   let ogg = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    leggiOggettoHSV(ogg, scala: 1000.0, a: &luce)
                } else if let ogg = valore as? [String: Any] {
                    leggiOggettoHSV(ogg, scala: 1000.0, a: &luce)
                }
            case "colour_data":
                if let s = valore as? String, s.count == 12 {
                    // Formato esadecimale HHHHSSSSVVVV (0000..0168, 0000..03e8, 0000..03e8)
                    let h = Int(s.prefix(4), radix: 16) ?? 0
                    let sat = Int(s.dropFirst(4).prefix(4), radix: 16) ?? 1000
                    let val = Int(s.suffix(4), radix: 16) ?? 1000
                    luce.tonalita = min(1, max(0, Double(h) / 360.0))
                    luce.saturazione = min(1, max(0, Double(sat) / (sat > 255 ? 1000.0 : 255.0)))
                    luce.luminosita = min(1, max(0.01, Double(val) / (val > 255 ? 1000.0 : 255.0)))
                }
            default:
                break
            }
        }
    }

    private func leggiOggettoHSV(_ ogg: [String: Any], scala: Double, a luce: inout Luce) {
        if let h = valoreNumerico(ogg["h"]) { luce.tonalita = min(1, max(0, h / 360.0)) }
        if let s = valoreNumerico(ogg["s"]) { luce.saturazione = min(1, max(0, s / scala)) }
        if let v = valoreNumerico(ogg["v"]) { luce.luminosita = min(1, max(0.01, v / scala)) }
    }

    private func valoreNumerico(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    // MARK: - Invio comandi Cloud

    func inviaStato(_ luce: Luce, credenziali: CredenzialiTuya) async -> Bool {
        guard credenziali.configurate, let tuyaId = luce.tuyaId else { return false }
        var comandi: [[String: Any]] = [
            ["code": luce.codiceSwitchTuya, "value": luce.accensione]
        ]

        if luce.accensione && luce.schemaTuya != .soloInterruttore {
            switch luce.modo {
            case .bianco:
                comandi.append(["code": "work_mode", "value": "white"])
                if luce.schemaTuya == .luceV2 {
                    let lum = Int((10.0 + min(1, max(0, luce.luminosita)) * 990.0).rounded())
                    let temp = Int((min(1, max(0, luce.temperatura)) * 1000.0).rounded())
                    comandi.append(["code": "bright_value_v2", "value": lum])
                    comandi.append(["code": "temp_value_v2", "value": temp])
                } else {
                    let lum = Int((25.0 + min(1, max(0, luce.luminosita)) * 230.0).rounded())
                    let temp = Int((min(1, max(0, luce.temperatura)) * 255.0).rounded())
                    comandi.append(["code": "bright_value", "value": lum])
                    comandi.append(["code": "temp_value", "value": temp])
                }
            case .colore, .effetto:
                comandi.append(["code": "work_mode", "value": "colour"])
                let h = Int((min(1, max(0, luce.tonalita)) * 360.0).rounded()) % 360
                if luce.schemaTuya == .luceV2 {
                    let s = Int((min(1, max(0, luce.saturazione)) * 1000.0).rounded())
                    let v = Int((max(0.01, min(1, luce.luminosita)) * 1000.0).rounded())
                    comandi.append(["code": "colour_data_v2", "value": ["h": h, "s": s, "v": v]])
                } else {
                    let s = Int((min(1, max(0, luce.saturazione)) * 255.0).rounded())
                    let v = Int((max(0.01, min(1, luce.luminosita)) * 255.0).rounded())
                    comandi.append(["code": "colour_data", "value": ["h": h, "s": s, "v": v]])
                }
            }
        }

        guard let corpo = try? JSONSerialization.data(withJSONObject: ["commands": comandi]) else { return false }

        if let r1 = try? await eseguiConRiprova(
            metodo: "POST",
            percorso: "/v1.0/iot-03/devices/\(tuyaId)/commands",
            corpo: corpo,
            credenziali: credenziali
        ), (r1["success"] as? Bool) == true {
            return true
        }

        // Riserva su /v1.0/devices/{id}/commands
        if let r2 = try? await eseguiConRiprova(
            metodo: "POST",
            percorso: "/v1.0/devices/\(tuyaId)/commands",
            corpo: corpo,
            credenziali: credenziali
        ), (r2["success"] as? Bool) == true {
            return true
        }
        return false
    }
}
