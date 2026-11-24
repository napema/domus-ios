import Foundation
import SwiftUI

/// Il contenitore condiviso tra Domus e i suoi widget.
/// Come in Life, chi firma l'IPA con SideStore / AltStore aggiunge il proprio suffisso agli App Group (`ALTAppGroups`):
/// il gruppo va quindi ricavato dinamicamente, con fallback sulla cartella documenti se l'IPA è quello senza widget.
enum GruppoDomus {
    private static var idApp: String {
        let id = Bundle.main.bundleIdentifier ?? "it.domus.app"
        guard Bundle.main.bundleURL.pathExtension == "appex" else { return id }
        return id.split(separator: ".").dropLast().joined(separator: ".")
    }

    static let contenitore: URL? = {
        let dichiarati = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        for gruppo in dichiarati + ["group.\(idApp)"] {
            if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gruppo) {
                return u
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }()

    static func file(_ nome: String) -> URL? {
        contenitore?.appendingPathComponent(nome)
    }
}

/// Instradamento URL (`domus://`) condiviso tra app e widget (anche ad avvio a freddo).
enum LinkDomus {
    private static func url(_ s: String) -> URL { URL(string: "domus://\(s)")! }
    static let luci = url("luci")
    static let strisce = url("strisce")
    static let aggiungi = url("aggiungi")
    static let impostazioni = url("impostazioni")
    static func luce(_ id: String) -> URL { url("luce/\(id)") }

    @MainActor static var gestore: ((URL) -> Void)?
    @MainActor private static var inAttesa: URL?
    private static let fileAttesa = "collegamento-domus.txt"

    @MainActor static func arrivato(_ u: URL) {
        if let gestore {
            gestore(u)
            return
        }
        inAttesa = u
        if let f = GruppoDomus.file(fileAttesa) {
            try? "\(Date().timeIntervalSince1970)|\(u.absoluteString)".write(to: f, atomically: true, encoding: .utf8)
        }
    }

    @MainActor static func prendiInAttesa() -> URL? {
        defer {
            inAttesa = nil
            if let f = GruppoDomus.file(fileAttesa) { try? FileManager.default.removeItem(at: f) }
        }
        if let u = inAttesa { return u }
        guard let f = GruppoDomus.file(fileAttesa), let s = try? String(contentsOf: f, encoding: .utf8) else { return nil }
        let parti = s.split(separator: "|", maxSplits: 1).map(String.init)
        guard parti.count == 2, let quando = Double(parti[0]), Date().timeIntervalSince1970 - quando < 20 else { return nil }
        return URL(string: parti[1])
    }
}

enum MarcaLuce: String, Codable, CaseIterable, Identifiable, Sendable {
    case tuya = "tuya"
    case magicHome = "magichome"

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .tuya: return "Tuya"
        case .magicHome: return "Magic Home"
        }
    }

    var coloreHex: String {
        switch self {
        case .tuya: return "#FF6B2C"
        case .magicHome: return "#38B6FF"
        }
    }
}

enum TipoLuce: String, Codable, CaseIterable, Identifiable, Sendable {
    case lampadina = "lampadina"
    case striscia = "striscia"

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .lampadina: return "Lampadina"
        case .striscia: return "Striscia LED"
        }
    }

    var simbolo: String {
        switch self {
        case .lampadina: return "lightbulb.led.fill"
        case .striscia: return "light.strip.2"
        }
    }
}

enum ModoLuce: String, Codable, CaseIterable, Identifiable, Sendable {
    case bianco = "bianco"
    case colore = "colore"
    case effetto = "effetto"

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .bianco: return "Bianco"
        case .colore: return "Colore"
        case .effetto: return "Effetti"
        }
    }

    var simbolo: String {
        switch self {
        case .bianco: return "thermometer.sun.fill"
        case .colore: return "paintpalette.fill"
        case .effetto: return "sparkles"
        }
    }
}

/// Mappatura dei Data Point (DP) Tuya: supporta sia lampadine/strisce moderne v2 (DP 20..25, scala 10..1000)
/// sia modelli classici v1 (DP 1..5, scala 25..255) e controller on/off (`switch_1`).
enum SchemaTuya: String, Codable, CaseIterable, Identifiable, Sendable {
    case luceV2 = "v2"
    case luceV1 = "v1"
    case soloInterruttore = "switch"
    case lucePixel = "pixel"

    var id: String { rawValue }

    var descrizione: String {
        switch self {
        case .lucePixel: return "Striscia colore (DP 20–24 · 1000)"
        case .luceV2: return "Luce Tuya v2 (DP 20–25 · 1000)"
        case .luceV1: return "Luce Tuya v1 (DP 1–5 · 255)"
        case .soloInterruttore: return "Interruttore LED (DP 1)"
        }
    }
}

/// Variante hardware dei controller Zengge / Magic Home (porta TCP 5577) e BroadLink (UDP 80).
enum VarianteMagicHome: String, Codable, CaseIterable, Identifiable, Sendable {
    case rgbw = "rgbw"           // 8 byte con maschera 0xF0 / 0x0F (strisce e lampadine RGBW)
    case rgbcct = "rgbcct"       // 9 byte con WW + CW e maschera 0xF0 / 0x0F (lampadine RGB+CCT)
    case rgbClassico = "rgb"     // 8 byte con maschera 0x00 (strisce RGB classiche a 3 canali)
    case dimmer = "dimmer"       // Monocromatico
    case broadlink = "broadlink" // Lampadine Magic Home / BroadLink LB1 (0x60C8 su UDP 80)

    var id: String { rawValue }

    var descrizione: String {
        switch self {
        case .rgbw: return "RGB + Bianco (8 byte · 5577)"
        case .rgbcct: return "RGB + Bianco Caldo/Freddo (9 byte · 5577)"
        case .rgbClassico: return "Striscia RGB classica (5577)"
        case .dimmer: return "Dimmer monocromatico (5577)"
        case .broadlink: return "Magic Home / BroadLink (UDP 80)"
        }
    }
}

struct Luce: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var nome: String
    var stanza: String
    var marca: MarcaLuce
    var tipo: TipoLuce

    // Stato luminoso normalizzato (indipendente dal protocollo sottostante)
    var accensione: Bool = false
    var luminosita: Double = 0.85       // 0.01 ... 1.0
    var temperatura: Double = 0.35      // 0.0 (2700K caldo) ... 1.0 (6500K freddo)
    var tonalita: Double = 0.08         // 0.0 ... 1.0 (0° ... 360°)
    var saturazione: Double = 0.85      // 0.0 ... 1.0
    var modo: ModoLuce = .bianco
    var effetto: Int = 0x25             // Codice effetto Magic Home (0x25..0x38) o indice scena Tuya
    var velocitaEffetto: Double = 0.65  // 0.0 ... 1.0

    // Parametri di rete (LAN + Cloud)
    var ip: String? = nil
    var porta: Int = 5577
    var mac: String? = nil
    var tuyaId: String? = nil
    var localKey: String? = nil
    var versioneProtocollo: String = "3.3"
    var codiceSwitchTuya: String = "switch_led"
    var schemaTuya: SchemaTuya = .luceV2
    var varianteMagic: VarianteMagicHome = .rgbw

    var online: Bool = true
    var viaLocale: Bool = false
    var preferitaWidget: Bool = true

    /// Temperatura espressa in Kelvin (2700K – 6500K).
    var kelvin: Int {
        Int((2700.0 + min(1, max(0, temperatura)) * 3800.0).rounded())
    }

    /// Componenti RGB (0...255) calcolate da tonalità, saturazione e luminosità.
    var rgb: (r: UInt8, g: UInt8, b: UInt8) {
        calcolaRGB(luminosita: luminosita)
    }

    /// Componenti RGB pure a luminosità piena (100%), utili quando il protocollo trasmette separatamente `brightness`.
    var rgbPuro: (r: UInt8, g: UInt8, b: UInt8) {
        calcolaRGB(luminosita: 1.0)
    }

    private func calcolaRGB(luminosita val: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        let h = min(1, max(0, tonalita))
        let s = min(1, max(0, saturazione))
        let v = min(1, max(0, val))
        let i = Int((h * 6.0).rounded(.down))
        let f = h * 6.0 - Double(i)
        let p = v * (1.0 - s)
        let q = v * (1.0 - f * s)
        let t = v * (1.0 - (1.0 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return (
            UInt8(min(255, max(0, Int((r * 255.0).rounded())))),
            UInt8(min(255, max(0, Int((g * 255.0).rounded())))),
            UInt8(min(255, max(0, Int((b * 255.0).rounded()))))
        )
    }

    /// Colore visivo corrente della luce per l'interfaccia Liquid Glass e i widget.
    var coloreVisivo: Color {
        if !accensione {
            return Color.gray.opacity(0.45)
        }
        switch modo {
        case .bianco:
            // Dal bianco ambrato caldo (2700K) al bianco ghiaccio (6500K)
            let t = min(1, max(0, temperatura))
            let r = 1.0 - t * 0.14
            let g = 0.76 + t * 0.18
            let b = 0.46 + t * 0.54
            return Color(red: r, green: g, blue: b)
        case .colore:
            return Color(hue: min(1, max(0, tonalita)), saturation: max(0.18, saturazione), brightness: 0.98)
        case .effetto:
            return EffettoLuce.colore(perCodice: effetto)
        }
    }

    mutating func impostaDaRGB(r: UInt8, g: UInt8, b: UInt8) {
        let rf = Double(r) / 255.0
        let gf = Double(g) / 255.0
        let bf = Double(b) / 255.0
        let maxC = max(rf, gf, bf)
        let minC = min(rf, gf, bf)
        let delta = maxC - minC

        var h = 0.0
        if delta > 0.0001 {
            if maxC == rf {
                h = ((gf - bf) / delta).truncatingRemainder(dividingBy: 6.0)
            } else if maxC == gf {
                h = ((bf - rf) / delta) + 2.0
            } else {
                h = ((rf - gf) / delta) + 4.0
            }
            h /= 6.0
            if h < 0 { h += 1.0 }
        }
        tonalita = h
        saturazione = maxC == 0 ? 0 : (delta / maxC)
        if maxC > 0.02 { luminosita = maxC }
    }
}

extension Luce {
    /// RGB (0...1) che simula un bianco alla temperatura data su LED solo-RGB (2700K ambra → 6500K freddo).
    static func rgbBianco(temperatura: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(1, max(0, temperatura))
        if t < 0.4 {
            let k = t / 0.4
            return (1.0, 0.58 + 0.24 * k, 0.16 + 0.48 * k)
        }
        let k = (t - 0.4) / 0.6
        return (1.0, 0.82 + 0.16 * k, 0.64 + 0.35 * k)
    }

    /// Tonalità e saturazione (0...1) del bianco simulato, per strisce che hanno solo il colore.
    var hsBiancoSimulato: (h: Double, s: Double) {
        let c = Luce.rgbBianco(temperatura: temperatura)
        let delta = 1.0 - c.b
        if delta < 0.001 { return (0, 0) }
        return (min(1, max(0, ((c.g - c.b) / delta) / 6.0)), delta)
    }
}

enum RegioneTuya: String, Codable, CaseIterable, Identifiable, Sendable {
    case eu = "https://openapi.tuyaeu.com"
    case euOvest = "https://openapi-weaz.tuyaeu.com"
    case us = "https://openapi.tuyaus.com"
    case cn = "https://openapi.tuyacn.com"
    case india = "https://openapi.tuyain.com"

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .eu: return "Europa Centrale (predefinito Italia)"
        case .euOvest: return "Europa Occidentale"
        case .us: return "Stati Uniti"
        case .cn: return "Cina"
        case .india: return "India"
        }
    }
}

struct CredenzialiTuya: Codable, Equatable, Sendable {
    var accessId: String = ""
    var accessSecret: String = ""
    var regione: RegioneTuya = .eu
    var uidUtente: String = ""

    var configurate: Bool {
        !accessId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ColoreSalvato: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var tonalita: Double
    var saturazione: Double
    var luminosita: Double = 1.0

    var colore: Color {
        Color(hue: min(1, max(0, tonalita)), saturation: min(1, max(0, saturazione)), brightness: max(0.25, luminosita))
    }
}

struct RoutineSveglia: Codable, Equatable, Sendable {
    var attiva: Bool = false
    var ora: Int = 6
    var minuto: Int = 40
    var minutiPrima: Int = 3
    var livelloSveglia: Double = 0.80
    var livelloDopoMinuto: Double = 1.0
    var tonalita: Double = 0.0
    var saturazione: Double = 1.0
    var soloBianco: Bool = false
    var temperatura: Double = 0.05

    var orarioFormattato: String {
        String(format: "%02d:%02d", ora, minuto)
    }
}

struct EffettoLuce: Identifiable, Hashable, Sendable {
    let codice: Int
    let nome: String
    let simbolo: String
    let hex: String

    var id: Int { codice }

    static let tutti: [EffettoLuce] = [
        EffettoLuce(codice: 0x25, nome: "Aurora 7 colori", simbolo: "sparkles", hex: "#AF52DE"),
        EffettoLuce(codice: 0x26, nome: "Respiro Ambra", simbolo: "flame.fill", hex: "#FF6B2C"),
        EffettoLuce(codice: 0x2A, nome: "Respiro Oceano", simbolo: "drop.fill", hex: "#38B6FF"),
        EffettoLuce(codice: 0x27, nome: "Foresta Viva", simbolo: "leaf.fill", hex: "#34C759"),
        EffettoLuce(codice: 0x2B, nome: "Tramonto Neon", simbolo: "sun.haze.fill", hex: "#FF2D55"),
        EffettoLuce(codice: 0x29, nome: "Luce Solare", simbolo: "sun.max.fill", hex: "#FFD60A"),
        EffettoLuce(codice: 0x38, nome: "Festa Dinamica", simbolo: "party.popper.fill", hex: "#5E5CE6"),
        EffettoLuce(codice: 0x2C, nome: "Ghiaccio Artico", simbolo: "snowflake", hex: "#64D2FF"),
    ]

    static func colore(perCodice codice: Int) -> Color {
        let hex = tutti.first(where: { $0.codice == codice })?.hex ?? "#AF52DE"
        return Color(esadecimale: hex)
    }

    /// Costruisce il payload Base64 per DP 51 (`dreamlight_scene_mode`) delle strisce SPI Tuya.
    static func payloadDreamlight(codiceEffetto: Int, velocita: Double, luminosita: Double) -> String {
        let speed = UInt8(max(1, min(100, Int((velocita * 95.0 + 5.0).rounded()))))
        let bright = UInt8(max(10, min(100, Int((luminosita * 100.0).rounded()))))
        let stile: UInt8
        let palette: [(UInt16, UInt8)]

        switch codiceEffetto {
        case 0x25: // Aurora 7 colori -> Rainbow
            stile = 0x0B
            palette = [(0, 100), (60, 100), (120, 100), (180, 100), (240, 100), (300, 100)]
        case 0x26: // Respiro Ambra -> Gradient caldo
            stile = 0x01
            palette = [(12, 95), (28, 95), (42, 90)]
        case 0x2A: // Respiro Oceano -> Flowing blu/ciano
            stile = 0x0A
            palette = [(190, 95), (215, 95), (245, 90)]
        case 0x27: // Foresta Viva -> Gradient verde
            stile = 0x01
            palette = [(110, 95), (145, 90), (170, 85)]
        case 0x2B: // Tramonto Neon -> Flowing rosa/arancio/viola
            stile = 0x0A
            palette = [(340, 95), (15, 95), (280, 90)]
        case 0x29: // Luce Solare -> Gradient oro/ambra
            stile = 0x01
            palette = [(45, 95), (30, 85), (55, 70)]
        case 0x38: // Festa Dinamica -> Jump rapido multicolore
            stile = 0x10
            palette = [(0, 100), (120, 100), (240, 100), (60, 100), (300, 100)]
        case 0x2C: // Ghiaccio Artico -> Chase ciano/blu/bianco
            stile = 0x08
            palette = [(195, 85), (215, 95), (200, 30)]
        default:
            stile = 0x01
            palette = [(280, 90), (200, 90), (340, 90)]
        }

        var bytes: [UInt8] = [0x01, 0xC9, stile, speed, bright, 0x00]
        for (h, s) in palette {
            let hue = min(359, h)
            bytes.append(UInt8((hue >> 8) & 0xFF))
            bytes.append(UInt8(hue & 0xFF))
            bytes.append(min(100, s))
        }
        return Data(bytes).base64EncodedString()
    }

    /// Costruisce la stringa JSON per `scene_data_v2` (DP 25) delle lampadine Tuya v2 (es. ANTELA Smart Bulb).
    static func scenaTuyaV2(codiceEffetto: Int, luminosita: Double) -> String {
        let v = max(50, min(1000, Int((luminosita * 1000.0).rounded())))
        let num = max(1, min(8, (tutti.firstIndex(where: { $0.codice == codiceEffetto }) ?? 0) + 1))
        let jump = (codiceEffetto == 0x38)
        let mode = jump ? "jump" : "gradient"
        let durata = jump ? 35 : 70
        let tonalita: [Int]
        switch codiceEffetto {
        case 0x25: tonalita = [0, 120, 240, 300]
        case 0x26: tonalita = [15, 32, 8]
        case 0x2A: tonalita = [195, 225, 255]
        case 0x27: tonalita = [110, 150, 85]
        case 0x2B: tonalita = [340, 20, 285]
        case 0x29: tonalita = [45, 30, 55]
        case 0x38: tonalita = [0, 90, 180, 270]
        case 0x2C: tonalita = [195, 210, 180]
        default: tonalita = [0, 120, 240]
        }

        let units: [[String: Any]] = tonalita.map { h in
            [
                "bright": 0,
                "h": h,
                "s": 1000,
                "temperature": 0,
                "unit_change_mode": mode,
                "unit_gradient_duration": durata,
                "unit_switch_duration": durata,
                "v": v,
            ]
        }
        let obj: [String: Any] = ["scene_num": num, "scene_units": units]
        if let d = try? JSONSerialization.data(withJSONObject: obj),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "{\"scene_num\":1,\"scene_units\":[{\"bright\":0,\"h\":240,\"s\":1000,\"temperature\":0,\"unit_change_mode\":\"gradient\",\"unit_gradient_duration\":70,\"unit_switch_duration\":70,\"v\":\(v)}]}"
    }
}

extension Color {
    init(esadecimale: String) {
        var s = esadecimale.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 3 {
            self.init(
                red: Double((v >> 8) & 0xF) / 15.0,
                green: Double((v >> 4) & 0xF) / 15.0,
                blue: Double(v & 0xF) / 15.0
            )
        } else {
            self.init(
                red: Double((v >> 16) & 0xFF) / 255.0,
                green: Double((v >> 8) & 0xFF) / 255.0,
                blue: Double(v & 0xFF) / 255.0
            )
        }
    }
}
