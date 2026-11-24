import SwiftUI

struct DettaglioLuce: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @Environment(\.dismiss) private var chiudi
    let idLuce: String

    @State private var mostraParametriRete = false
    @Namespace private var spazioModo

    var body: some View {
        if let indice = gestore.luci.firstIndex(where: { $0.id == idLuce }) {
            let luce = gestore.luci[indice]
            contenuto(luce: luce)
        } else {
            ContentUnavailableView("Luce non trovata", systemImage: "lightbulb.slash")
        }
    }

    @ViewBuilder
    private func contenuto(luce: Luce) -> some View {
        let colore = luce.coloreVisivo

        NavigationStack {
            ZStack {
                SfondoAurora(luci: [luce])

                ScrollView {
                    VStack(spacing: 18) {
                        intestazioneLuminosa(luce: luce, colore: colore)
                        selettoreModo(luce: luce)

                        CartaVetro(tinta: colore.opacity(luce.accensione ? 0.10 : 0.0)) {
                            BarraTattileVetro(
                                titolo: "Luminosità",
                                simbolo: "sun.max.fill",
                                valore: Binding(
                                    get: { luce.luminosita },
                                    set: { nuovo in
                                        var m = gestore.luce(id: luce.id) ?? luce
                                        m.accensione = true
                                        m.luminosita = nuovo
                                        gestore.aggiorna(m, immediato: false)
                                    }
                                ),
                                coloreBarra: luce.accensione ? colore : .accentoDomus,
                                alRilascio: {
                                    if let aggiornata = gestore.luce(id: luce.id) {
                                        gestore.aggiorna(aggiornata, immediato: true)
                                    }
                                }
                            )
                        }

                        pannelloModalita(luce: luce)
                        sezioneConfigurazioneDispositivo(luce: luce)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(luce.nome)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { chiudi() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func intestazioneLuminosa(luce: Luce, colore: Color) -> some View {
        CartaVetro(tinta: luce.accensione ? colore.opacity(0.18) : nil, raggio: 28, padding: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(luce.accensione ? colore.opacity(0.32) : Color.primary.opacity(0.08))
                        .frame(width: 68, height: 68)
                        .shadow(color: luce.accensione ? colore.opacity(0.65) : .clear, radius: 18)
                    Image(systemName: luce.tipo.simbolo)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(luce.accensione ? colore : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(luce.stanza)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(descrizioneStato(luce))
                        .font(.headline)
                    EtichettaProtocollo(luce: luce)
                }

                Spacer()

                Button {
                    gestore.commuta(luce.id)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(luce.accensione ? Color.black : Color.primary)
                        .background(luce.accensione ? colore : Color.primary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func descrizioneStato(_ luce: Luce) -> String {
        guard luce.accensione else { return "Spenta" }
        let perc = Int((luce.luminosita * 100).rounded())
        switch luce.modo {
        case .bianco:
            return "Bianco \(luce.kelvin)K · \(perc)%"
        case .colore:
            return "Colore RGB · \(perc)%"
        case .effetto:
            let nomeEff = EffettoLuce.tutti.first { $0.codice == luce.effetto }?.nome ?? "Effetto"
            return "\(nomeEff) · \(perc)%"
        }
    }

    private func selettoreModo(luce: Luce) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ModoLuce.allCases) { modo in
                    let attivo = luce.modo == modo
                    Button {
                        toccoSelezione()
                        var m = luce
                        m.accensione = true
                        m.modo = modo
                        gestore.aggiorna(m, immediato: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: modo.simbolo)
                            Text(modo.etichetta)
                                .fontWeight(attivo ? .semibold : .medium)
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .glassEffect(
                            attivo ? .regular.tint(Color.accentoDomus.opacity(0.32)).interactive() : .regular.interactive(),
                            in: .capsule
                        )
                        .glassEffectID("modo-\(modo.rawValue)", in: spazioModo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func pannelloModalita(luce: Luce) -> some View {
        switch luce.modo {
        case .bianco:
            CartaVetro {
                SelettoreBiancoVetro(
                    temperatura: Binding(
                        get: { luce.temperatura },
                        set: { nuovo in
                            var m = gestore.luce(id: luce.id) ?? luce
                            m.accensione = true
                            m.modo = .bianco
                            m.temperatura = nuovo
                            gestore.aggiorna(m, immediato: false)
                        }
                    ),
                    kelvin: luce.kelvin
                ) { finale in
                    if finale, let aggiornata = gestore.luce(id: luce.id) {
                        gestore.aggiorna(aggiornata, immediato: true)
                    }
                }
            }

        case .colore:
            CartaVetro {
                DiscoColoreVetro(
                    tonalita: Binding(
                        get: { luce.tonalita },
                        set: { h in
                            var m = gestore.luce(id: luce.id) ?? luce
                            m.accensione = true
                            m.modo = .colore
                            m.tonalita = h
                            gestore.aggiorna(m, immediato: false)
                        }
                    ),
                    saturazione: Binding(
                        get: { luce.saturazione },
                        set: { s in
                            var m = gestore.luce(id: luce.id) ?? luce
                            m.accensione = true
                            m.modo = .colore
                            m.saturazione = s
                            gestore.aggiorna(m, immediato: false)
                        }
                    ),
                    coloriSalvati: gestore.coloriSalvati,
                    alPreset: {
                        var m = gestore.luce(id: luce.id) ?? luce
                        m.accensione = true
                        m.modo = .colore
                        m.luminosita = 1.0
                        gestore.aggiorna(m, immediato: true)
                    },
                    applicaSalvato: { salvato in
                        var m = gestore.luce(id: luce.id) ?? luce
                        m.accensione = true
                        m.modo = .colore
                        m.tonalita = salvato.tonalita
                        m.saturazione = salvato.saturazione
                        m.luminosita = salvato.luminosita
                        gestore.aggiorna(m, immediato: true)
                    },
                    salvaColore: {
                        let corr = gestore.luce(id: luce.id) ?? luce
                        gestore.salvaColoreCorrente(tonalita: corr.tonalita, saturazione: corr.saturazione, luminosita: corr.luminosita)
                    },
                    eliminaColore: { idColore in
                        gestore.eliminaColoreSalvato(id: idColore)
                    }
                ) { finale in
                    if finale, let aggiornata = gestore.luce(id: luce.id) {
                        gestore.aggiorna(aggiornata, immediato: true)
                    }
                }
            }

        case .effetto:
            CartaVetro {
                Text("Effetti dinamici")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(EffettoLuce.tutti) { eff in
                        let scelto = luce.effetto == eff.codice
                        let c = Color(esadecimale: eff.hex)
                        Button {
                            toccoSelezione()
                            var m = luce
                            m.accensione = true
                            m.modo = .effetto
                            m.effetto = eff.codice
                            gestore.aggiorna(m, immediato: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: eff.simbolo)
                                    .foregroundStyle(c)
                                Text(eff.nome)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .glassEffect(
                                scelto ? .regular.tint(c.opacity(0.32)).interactive() : .regular.interactive(),
                                in: .rect(cornerRadius: 16)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if luce.marca == .magicHome || luce.schemaTuya == .lucePixel {
                    BarraTattileVetro(
                        titolo: "Velocità transizione",
                        simbolo: "hare.fill",
                        valore: Binding(
                            get: { luce.velocitaEffetto },
                            set: { v in
                                var m = gestore.luce(id: luce.id) ?? luce
                                m.velocitaEffetto = v
                                gestore.aggiorna(m, immediato: false)
                            }
                        ),
                        minimo: 0.0,
                        coloreBarra: .cianoDomus,
                        alRilascio: {
                            if let aggiornata = gestore.luce(id: luce.id) {
                                gestore.aggiorna(aggiornata, immediato: true)
                            }
                        }
                    )
                    .padding(.top, 6)
                }
            }
        }
    }

    private func sezioneConfigurazioneDispositivo(luce: Luce) -> some View {
        CartaVetro {
            DisclosureGroup(isExpanded: $mostraParametriRete) {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().padding(.top, 4)

                    campoTesto(etichetta: "Nome", valore: luce.nome) { nuovo in
                        var m = luce; m.nome = nuovo; gestore.aggiungiOModifica(m)
                    }

                    campoTesto(etichetta: "Stanza", valore: luce.stanza) { nuovo in
                        var m = luce; m.stanza = nuovo; gestore.aggiungiOModifica(m)
                    }

                    Picker("Tipo dispositivo", selection: Binding(
                        get: { luce.tipo },
                        set: { nuovo in var m = gestore.luce(id: luce.id) ?? luce; m.tipo = nuovo; gestore.aggiungiOModifica(m) }
                    )) {
                        ForEach(TipoLuce.allCases) { t in
                            Text(t.etichetta).tag(t)
                        }
                    }

                    Toggle("Mostra nei widget rapidi", isOn: Binding(
                        get: { luce.preferitaWidget },
                        set: { v in var m = gestore.luce(id: luce.id) ?? luce; m.preferitaWidget = v; gestore.aggiungiOModifica(m) }
                    ))
                    .font(.subheadline)

                    campoTesto(etichetta: "Indirizzo IP locale", valore: luce.ip ?? "", tastiera: .numbersAndPunctuation) { nuovo in
                        var m = luce
                        let pulito = nuovo.trimmingCharacters(in: .whitespacesAndNewlines)
                        m.ip = pulito.isEmpty ? nil : pulito
                        gestore.aggiungiOModifica(m)
                    }

                    if luce.marca == .magicHome {
                        Picker("Protocollo Magic Home", selection: Binding(
                            get: { luce.varianteMagic },
                            set: { v in var m = gestore.luce(id: luce.id) ?? luce; m.varianteMagic = v; gestore.aggiungiOModifica(m) }
                        )) {
                            ForEach(VarianteMagicHome.allCases) { v in
                                Text(v.descrizione).tag(v)
                            }
                        }
                        .font(.subheadline)
                    } else {
                        campoTesto(etichetta: "Device ID Tuya", valore: luce.tuyaId ?? "") { nuovo in
                            var m = luce; m.tuyaId = nuovo.trimmingCharacters(in: .whitespacesAndNewlines); gestore.aggiungiOModifica(m)
                        }
                        campoTesto(etichetta: "Local Key (16 caratteri)", valore: luce.localKey ?? "") { nuovo in
                            var m = luce; m.localKey = nuovo.trimmingCharacters(in: .whitespacesAndNewlines); gestore.aggiungiOModifica(m)
                        }
                        Picker("Versione LAN Tuya", selection: Binding(
                            get: { luce.versioneProtocollo },
                            set: { v in var m = gestore.luce(id: luce.id) ?? luce; m.versioneProtocollo = v; gestore.aggiungiOModifica(m) }
                        )) {
                            Text("3.3").tag("3.3")
                            Text("3.4").tag("3.4")
                            Text("3.5").tag("3.5")
                        }
                        .pickerStyle(.segmented)

                        Picker("Schema DP", selection: Binding(
                            get: { luce.schemaTuya },
                            set: { s in var m = gestore.luce(id: luce.id) ?? luce; m.schemaTuya = s; gestore.aggiungiOModifica(m) }
                        )) {
                            ForEach(SchemaTuya.allCases) { s in
                                Text(s.descrizione).tag(s)
                            }
                        }
                        .font(.subheadline)
                    }

                    Button(role: .destructive) {
                        let id = luce.id
                        chiudi()
                        gestore.elimina(id)
                    } label: {
                        Label("Rimuovi questa luce", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .tint(.pericoloDomus)
                }
            } label: {
                Label("Stanza, widget e parametri di rete", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func campoTesto(
        etichetta: String,
        valore: String,
        tastiera: UIKeyboardType = .default,
        alCambio: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(etichetta)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(etichetta, text: Binding(get: { valore }, set: alCambio))
                .keyboardType(tastiera)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
