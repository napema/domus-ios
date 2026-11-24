import SwiftUI

struct VistaLuci: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @State private var stanzaSelezionata: String = "Tutte"
    @State private var marcaFiltro: MarcaLuce? = nil
    @Namespace private var spazioVetro

    private var luciFiltrate: [Luce] {
        gestore.luci.filter { luce in
            let okStanza = (stanzaSelezionata == "Tutte" || luce.stanza == stanzaSelezionata)
            let okMarca = (marcaFiltro == nil || luce.marca == marcaFiltro)
            return okStanza && okMarca
        }
    }

    var body: some View {
        ZStack {
            SfondoAurora(luci: gestore.luci)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if gestore.luci.isEmpty {
                        statoVuotoIniziale
                    } else {
                        intestazioneAzioniRapide
                        filtriStanzeEMarche
                        barraSceneMiste
                        elencoLuci
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
            .refreshable {
                await gestore.aggiornaStatiDaRete()
            }
        }
        .navigationTitle("Domus")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        let trovate = await gestore.scansionaReteWiFi()
                        gestore.mostraAvviso(trovate > 0 ? "Rilevate o aggiornate \(trovate) luci in Wi-Fi" : "Scansione Wi-Fi completata")
                    }
                } label: {
                    if gestore.scansioneInCorso {
                        ProgressView()
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                }
                .accessibilityLabel("Scansiona Wi-Fi")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toccoLeggero()
                    gestore.mostraAggiungi = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Aggiungi luce")
            }
        }
    }

    // MARK: - Sezioni

    private var statoVuotoIniziale: some View {
        CartaVetro(tinta: Color.accentoDomus.opacity(0.12), raggio: 28, padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.2.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentoDomus)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Collega le tue luci")
                            .font(.title3.weight(.bold))
                        Text("Tuya & Magic Home in un'unica app nativa")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("• **Magic Home (魔法家)**: tocca «Scansiona Wi-Fi» per trovare subito lampadine e strisce LED sulla porta locale 5577 senza account.\n• **Tuya / Smart Life**: collega il tuo progetto Tuya Cloud per importare automaticamente tutte le luci e le `local_key` per il controllo istantaneo in LAN.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            let n = await gestore.scansionaReteWiFi()
                            gestore.mostraAvviso(n > 0 ? "Trovate \(n) luci sulla rete Wi-Fi!" : "Nessuna luce Magic Home rilevata automaticamente: riprova o aggiungi Tuya")
                        }
                    } label: {
                        Label(gestore.scansioneInCorso ? "Ricerca…" : "Scansiona Wi-Fi", systemImage: "wifi")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(gestore.scansioneInCorso)

                    Button {
                        gestore.mostraAggiungi = true
                    } label: {
                        Label("Configura Tuya", systemImage: "bolt.horizontal.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.top, 4)

                Button {
                    gestore.caricaEsempiDimostrativi()
                } label: {
                    Text("Prova l'interfaccia con luci dimostrative")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    private var intestazioneAzioniRapide: some View {
        let stanzaTarget = stanzaSelezionata == "Tutte" ? nil : stanzaSelezionata
        let sottolista = luciFiltrate
        let accese = sottolista.filter(\.accensione).count

        return GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stanzaSelezionata == "Tutte" ? "Tutta la casa" : stanzaSelezionata)
                        .font(.headline)
                    Text("\(accese) di \(sottolista.count) accese · \(gestore.luci.filter(\.viaLocale).count) in LAN diretta")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .glassEffectID("riepilogo", in: spazioVetro)

                Button {
                    gestore.impostaTutte(accese: true, inStanza: stanzaTarget)
                } label: {
                    Image(systemName: "sun.max.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 46, height: 48)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("Accendi tutte")

                Button {
                    gestore.impostaTutte(accese: false, inStanza: stanzaTarget)
                } label: {
                    Image(systemName: "moon.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 46, height: 48)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Spegni tutte")
            }
        }
    }

    private var filtriStanzeEMarche: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    PillolaVetro(titolo: "Tutte", icona: "house.fill", attiva: stanzaSelezionata == "Tutte") {
                        stanzaSelezionata = "Tutte"
                    }
                    ForEach(gestore.stanze, id: \.self) { stanza in
                        PillolaVetro(titolo: stanza, attiva: stanzaSelezionata == stanza) {
                            stanzaSelezionata = stanza
                        }
                    }

                    Divider().frame(height: 20).padding(.horizontal, 2)

                    ForEach(MarcaLuce.allCases) { marca in
                        PillolaVetro(
                            titolo: marca.etichetta,
                            attiva: marcaFiltro == marca,
                            tinta: Color(esadecimale: marca.coloreHex)
                        ) {
                            marcaFiltro = (marcaFiltro == marca ? nil : marca)
                        }
                    }
                }
            }
        }
    }

    private var barraSceneMiste: some View {
        let stanzaTarget = stanzaSelezionata == "Tutte" ? nil : stanzaSelezionata
        return VStack(alignment: .leading, spacing: 8) {
            Text("Atmosfere simultanee (Tuya + Magic Home)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    pulsanteScena(titolo: "Relax 2700K", icona: "flame.fill", tinta: Color(red: 1, green: 0.65, blue: 0.25)) {
                        gestore.applicaScena(modo: .bianco, temperatura: 0.05, luminosita: 0.65, stanza: stanzaTarget)
                    }
                    pulsanteScena(titolo: "Lettura 4500K", icona: "book.fill", tinta: Color(red: 1, green: 0.88, blue: 0.68)) {
                        gestore.applicaScena(modo: .bianco, temperatura: 0.48, luminosita: 0.95, stanza: stanzaTarget)
                    }
                    pulsanteScena(titolo: "Cinema Cyber", icona: "tv.fill", tinta: .cianoDomus) {
                        gestore.applicaScena(modo: .colore, tonalita: 0.58, saturazione: 0.90, luminosita: 0.55, stanza: stanzaTarget)
                    }
                    pulsanteScena(titolo: "Tramonto", icona: "sun.horizon.fill", tinta: Color(esadecimale: "#FF3B6B")) {
                        gestore.applicaScena(modo: .colore, tonalita: 0.95, saturazione: 0.88, luminosita: 0.80, stanza: stanzaTarget)
                    }
                    pulsanteScena(titolo: "Notte soffusa", icona: "sparkles", tinta: Color(esadecimale: "#7D5CFF")) {
                        gestore.applicaScena(modo: .bianco, temperatura: 0.0, luminosita: 0.12, stanza: stanzaTarget)
                    }
                }
            }
        }
    }

    private func pulsanteScena(titolo: String, icona: String, tinta: Color, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            HStack(spacing: 8) {
                Image(systemName: icona)
                    .foregroundStyle(tinta)
                Text(titolo)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(tinta.opacity(0.18)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var elencoLuci: some View {
        LazyVStack(spacing: 12) {
            if !gestore.statoScansione.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(gestore.statoScansione)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(luciFiltrate) { luce in
                TesseraLuceVetro(luce: luce)
            }
        }
    }
}
