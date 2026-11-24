import SwiftUI

/// Schermata dedicata alle strisce LED (sia Tuya che Magic Home):
/// permette di sincronizzare colore, intensità ed effetti dinamici su tutte le strisce contemporaneamente.
struct VistaStrisce: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @State private var tonalitaComune: Double = 0.58
    @State private var saturazioneComune: Double = 0.88
    @State private var luminositaComune: Double = 0.85

    var body: some View {
        let strisce = gestore.strisce

        ZStack {
            SfondoAurora(luci: strisce.isEmpty ? gestore.luci : strisce)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if strisce.isEmpty {
                        CartaVetro(raggio: 26, padding: 22) {
                            ContentUnavailableView(
                                "Nessuna striscia LED",
                                systemImage: "light.strip.2",
                                description: Text("Scansiona il Wi-Fi per trovare le strisce Magic Home o importa quelle Tuya. Puoi anche cambiare il tipo di una luce in «Striscia LED» dai suoi dettagli.")
                            )
                            Button {
                                gestore.mostraAggiungi = true
                            } label: {
                                Label("Aggiungi striscia LED", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                        }
                    } else {
                        regiaSincronizzata(conteggio: strisce.count)

                        Text("Le tue strisce LED (\(strisce.count))")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 4)

                        LazyVStack(spacing: 12) {
                            ForEach(strisce) { s in
                                TesseraLuceVetro(luce: s)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
        }
        .navigationTitle("Strisce LED")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    gestore.mostraAggiungi = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func regiaSincronizzata(conteggio: Int) -> some View {
        let coloreSync = Color(hue: tonalitaComune, saturation: saturazioneComune, brightness: 1.0)

        return CartaVetro(tinta: coloreSync.opacity(0.14), raggio: 28, padding: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sincronizza tutte le strisce")
                        .font(.headline)
                    Text("Unisce \(conteggio) strisce Tuya e Magic Home nello stesso colore")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Spegni") {
                    for s in gestore.strisce where s.accensione {
                        gestore.commuta(s.id)
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.glass)
            }

            DiscoColoreVetro(tonalita: $tonalitaComune, saturazione: $saturazioneComune) { finale in
                if finale {
                    gestore.applicaScena(
                        modo: .colore,
                        tonalita: tonalitaComune,
                        saturazione: saturazioneComune,
                        luminosita: luminositaComune,
                        soloStrisce: true
                    )
                }
            }

            BarraTattileVetro(
                titolo: "Intensità strisce",
                simbolo: "sun.max.fill",
                valore: $luminositaComune,
                coloreBarra: coloreSync
            ) {
                gestore.applicaScena(
                    modo: .colore,
                    tonalita: tonalitaComune,
                    saturazione: saturazioneComune,
                    luminosita: luminositaComune,
                    soloStrisce: true
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EffettoLuce.tutti) { eff in
                        Button {
                            gestore.applicaScena(
                                modo: .effetto,
                                tonalita: tonalitaComune,
                                luminosita: luminositaComune,
                                codiceEffetto: eff.codice,
                                soloStrisce: true
                            )
                        } label: {
                            Label(eff.nome, systemImage: eff.simbolo)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.tint(Color(esadecimale: eff.hex).opacity(0.24)).interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
