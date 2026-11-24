import AppIntents
import SwiftUI
import WidgetKit

/// Commuta una singola lampadina o striscia LED direttamente dal widget senza aprire Domus.
struct CommutaLuceIntent: AppIntent {
    static var title: LocalizedStringResource = "Commuta luce"
    static var isDiscoverable = false

    @Parameter(title: "ID Luce")
    var idLuce: String

    init() {}
    init(idLuce: String) { self.idLuce = idLuce }

    func perform() async throws -> some IntentResult {
        var luci = ArchivioCondiviso.caricaLuci()
        guard let idx = luci.firstIndex(where: { $0.id == idLuce }) else {
            return .result()
        }
        luci[idx].accensione.toggle()
        let bersaglio = luci[idx]
        ArchivioCondiviso.salvaLuci(luci)

        let cred = ArchivioCondiviso.caricaCredenzialiTuya()
        _ = await ControlloRapido.applica(bersaglio, credenzialiTuya: cred)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Accende o spegne tutte le luci dal widget o dal Centro di Controllo senza aprire l'app.
struct CommutaTutteLuciIntent: AppIntent {
    static var title: LocalizedStringResource = "Commuta tutte le luci"
    static var isDiscoverable = true

    func perform() async throws -> some IntentResult {
        var luci = ArchivioCondiviso.caricaLuci()
        guard !luci.isEmpty else { return .result() }
        let qualcunaAccesa = luci.contains(where: \.accensione)
        let nuovoStato = !qualcunaAccesa
        for idx in luci.indices {
            luci[idx].accensione = nuovoStato
        }
        ArchivioCondiviso.salvaLuci(luci)

        let cred = ArchivioCondiviso.caricaCredenzialiTuya()
        let copia = luci
        await withTaskGroup(of: Void.self) { gruppo in
            for l in copia {
                gruppo.addTask {
                    _ = await ControlloRapido.applica(l, credenzialiTuya: cred)
                }
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Apre Domus direttamente su una specifica lampadina/striscia o schermata (come `ApriLifeIntent` in Life).
struct ApriDomusIntent: AppIntent {
    static var title: LocalizedStringResource = "Apri Domus"
    static var isDiscoverable = false
    static var openAppWhenRun = true

    @Parameter(title: "Destinazione")
    var destinazione: String

    init() {}
    init(_ url: URL) { destinazione = url.absoluteString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let u = URL(string: destinazione) {
            LinkDomus.arrivato(u)
        }
        return .result()
    }
}

struct VoceWidgetDomus: TimelineEntry {
    let date: Date
    let luci: [Luce]
}

// MARK: - Viste Widget Schermata Home

struct VistaWidgetLuci: View {
    @Environment(\.widgetFamily) private var famiglia
    let voce: VoceWidgetDomus

    private var luciVisibili: [Luce] {
        let preferite = voce.luci.filter(\.preferitaWidget)
        let base = preferite.isEmpty ? voce.luci : preferite
        switch famiglia {
        case .systemSmall: return Array(base.prefix(2))
        case .systemMedium: return Array(base.prefix(4))
        default: return Array(base.prefix(8))
        }
    }

    var body: some View {
        let accese = voce.luci.filter(\.accensione).count

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: accese > 0 ? "lightbulb.led.fill" : "lightbulb")
                    .foregroundStyle(accese > 0 ? Color(esadecimale: "#FFB02E") : .secondary)
                    .font(.subheadline.weight(.semibold))

                Text(accese == 0 ? "Spente" : "\(accese) acces\(accese == 1 ? "a" : "e")")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if !voce.luci.isEmpty {
                    Button(intent: CommutaTutteLuciIntent()) {
                        Image(systemName: "power")
                            .font(.caption.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(accese > 0 ? Color(esadecimale: "#FFB02E").opacity(0.25) : Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if voce.luci.isEmpty {
                Spacer(minLength: 0)
                Text("Apri Domus per collegare le luci Tuya e Magic Home.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if famiglia == .systemSmall {
                VStack(spacing: 8) {
                    ForEach(luciVisibili) { luce in
                        rigaCompattaWidget(luce)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(luciVisibili) { luce in
                        tesseraInterattivaWidget(luce)
                    }
                }
            }
        }
    }

    private func rigaCompattaWidget(_ luce: Luce) -> some View {
        let c = luce.coloreVisivo
        return Button(intent: CommutaLuceIntent(idLuce: luce.id)) {
            HStack(spacing: 8) {
                Image(systemName: luce.tipo.simbolo)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(luce.accensione ? c : .secondary)
                Text(luce.nome)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                luce.accensione ? c.opacity(0.20) : Color.secondary.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func tesseraInterattivaWidget(_ luce: Luce) -> some View {
        let c = luce.coloreVisivo
        return HStack(spacing: 8) {
            Button(intent: CommutaLuceIntent(idLuce: luce.id)) {
                Image(systemName: luce.tipo.simbolo)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(luce.accensione ? .black : .secondary)
                    .background(luce.accensione ? c : Color.secondary.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)

            Button(intent: ApriDomusIntent(LinkDomus.luce(luce.id))) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(luce.nome)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(luce.accensione ? "\(Int((luce.luminosita * 100).rounded()))% · \(luce.marca.etichetta)" : "Spenta")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            luce.accensione ? c.opacity(0.16) : Color.secondary.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

// MARK: - Viste Widget Schermata di Blocco

struct VistaBloccoLuci: View {
    @Environment(\.widgetFamily) private var famiglia
    let voce: VoceWidgetDomus

    var body: some View {
        let accese = voce.luci.filter(\.accensione).count
        let tot = voce.luci.count

        switch famiglia {
        case .accessoryInline:
            Label(tot == 0 ? "Domus" : "\(accese)/\(tot) luci accese", systemImage: "lightbulb.led.fill")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: accese > 0 ? "lightbulb.led.fill" : "lightbulb")
                        .font(.caption.weight(.bold))
                    Text("\(accese)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                }
            }
        default:
            HStack(spacing: 8) {
                Image(systemName: accese > 0 ? "lightbulb.led.fill" : "moon.stars.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Domus")
                        .font(.headline)
                    Text(tot == 0 ? "Nessuna luce configurata" : (accese == 0 ? "Tutte le luci spente" : "\(accese) su \(tot) accese"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
