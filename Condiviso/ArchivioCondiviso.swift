import Foundation
import WidgetKit

/// Archivio condiviso tra Domus e DomusWidget: salva l'elenco delle luci e le credenziali Tuya Cloud
/// nel contenitore condiviso così i widget interattivi funzionano anche ad app chiusa.
enum ArchivioCondiviso {
    private static let fileLuci = "luci-domus.json"
    private static let fileTuya = "credenziali-tuya.json"
    private static let fileColori = "colori-salvati.json"
    private static let fileRoutine = "routine-sveglia.json"

    private static let codificatore: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decodificatore = JSONDecoder()

    static func caricaLuci() -> [Luce] {
        guard let url = GruppoDomus.file(fileLuci),
              let dati = try? Data(contentsOf: url),
              let luci = try? decodificatore.decode([Luce].self, from: dati) else {
            return []
        }
        return luci
    }

    static func salvaLuci(_ luci: [Luce], aggiornaWidget: Bool = true) {
        guard let url = GruppoDomus.file(fileLuci),
              let dati = try? codificatore.encode(luci) else { return }
        try? dati.write(to: url, options: .atomic)
        if aggiornaWidget {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func caricaCredenzialiTuya() -> CredenzialiTuya {
        guard let url = GruppoDomus.file(fileTuya),
              let dati = try? Data(contentsOf: url),
              let cred = try? decodificatore.decode(CredenzialiTuya.self, from: dati) else {
            return CredenzialiTuya()
        }
        return cred
    }

    static func salvaCredenzialiTuya(_ credenziali: CredenzialiTuya) {
        guard let url = GruppoDomus.file(fileTuya),
              let dati = try? codificatore.encode(credenziali) else { return }
        try? dati.write(to: url, options: .atomic)
    }

    static func caricaColoriSalvati() -> [ColoreSalvato] {
        guard let url = GruppoDomus.file(fileColori),
              let dati = try? Data(contentsOf: url),
              let elenco = try? decodificatore.decode([ColoreSalvato].self, from: dati) else {
            return []
        }
        return elenco
    }

    static func salvaColoriSalvati(_ colori: [ColoreSalvato]) {
        guard let url = GruppoDomus.file(fileColori),
              let dati = try? codificatore.encode(colori) else { return }
        try? dati.write(to: url, options: .atomic)
    }

    static func caricaRoutineSveglia() -> RoutineSveglia {
        guard let url = GruppoDomus.file(fileRoutine),
              let dati = try? Data(contentsOf: url),
              let routine = try? decodificatore.decode(RoutineSveglia.self, from: dati) else {
            return RoutineSveglia()
        }
        return routine
    }

    static func salvaRoutineSveglia(_ routine: RoutineSveglia) {
        guard let url = GruppoDomus.file(fileRoutine),
              let dati = try? codificatore.encode(routine) else { return }
        try? dati.write(to: url, options: .atomic)
    }

    /// Luci dimostrative realistiche (Tuya + Magic Home, lampadine e strisce LED) per anteprima o test.
    static let esempi: [Luce] = [
        Luce(
            id: "mh-strip-salotto",
            nome: "Striscia TV",
            stanza: "Salotto",
            marca: .magicHome,
            tipo: .striscia,
            accensione: true,
            luminosita: 0.88,
            temperatura: 0.30,
            tonalita: 0.58,
            saturazione: 0.82,
            modo: .colore,
            ip: "192.168.1.54",
            porta: 5577,
            varianteMagic: .rgbw,
            online: true,
            viaLocale: true
        ),
        Luce(
            id: "tuya-bulb-salotto",
            nome: "Piantana Angolo",
            stanza: "Salotto",
            marca: .tuya,
            tipo: .lampadina,
            accensione: true,
            luminosita: 0.76,
            temperatura: 0.22,
            tonalita: 0.08,
            saturazione: 0.70,
            modo: .bianco,
            ip: "192.168.1.61",
            porta: 6668,
            tuyaId: "bf91demo01salotto",
            localKey: "0123456789abcdef",
            versioneProtocollo: "3.4",
            schemaTuya: .luceV2,
            online: true,
            viaLocale: true
        ),
        Luce(
            id: "mh-strip-studio",
            nome: "LED Scrivania",
            stanza: "Studio",
            marca: .magicHome,
            tipo: .striscia,
            accensione: true,
            luminosita: 0.92,
            temperatura: 0.50,
            tonalita: 0.78,
            saturazione: 0.86,
            modo: .colore,
            ip: "192.168.1.58",
            porta: 5577,
            varianteMagic: .rgbw,
            online: true,
            viaLocale: true
        ),
        Luce(
            id: "tuya-bulb-camera",
            nome: "Abat-jour Letto",
            stanza: "Camera",
            marca: .tuya,
            tipo: .lampadina,
            accensione: false,
            luminosita: 0.40,
            temperatura: 0.12,
            tonalita: 0.06,
            saturazione: 0.65,
            modo: .bianco,
            ip: "192.168.1.64",
            porta: 6668,
            tuyaId: "bf91demo02camera",
            localKey: "fedcba9876543210",
            versioneProtocollo: "3.5",
            schemaTuya: .luceV2,
            online: true,
            viaLocale: true
        ),
        Luce(
            id: "tuya-strip-cucina",
            nome: "Sottopensile LED",
            stanza: "Cucina",
            marca: .tuya,
            tipo: .striscia,
            accensione: false,
            luminosita: 0.95,
            temperatura: 0.65,
            tonalita: 0.12,
            saturazione: 0.30,
            modo: .bianco,
            tuyaId: "bf91demo03cucina",
            versioneProtocollo: "3.3",
            schemaTuya: .luceV2,
            online: true,
            viaLocale: false
        ),
    ]
}
