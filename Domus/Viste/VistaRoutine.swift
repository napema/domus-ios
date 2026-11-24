import SwiftUI

struct VistaRoutine: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @State private var mostraGuidaOrologio = false

    private var dataSvegliaBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: gestore.routineSveglia.ora,
                    minute: gestore.routineSveglia.minuto,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { nuovaData in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: nuovaData)
                var r = gestore.routineSveglia
                r.ora = comps.hour ?? r.ora
                r.minuto = comps.minute ?? r.minuto
                gestore.salvaRoutineSveglia(r)
            }
        )
    }

    private func orarioSfasato(minutiDelta: Int) -> String {
        let tot = (gestore.routineSveglia.ora * 60 + gestore.routineSveglia.minuto + minutiDelta + 1440) % 1440
        return String(format: "%02d:%02d", tot / 60, tot % 60)
    }

    var body: some View {
        let r = gestore.routineSveglia
        let coloreTarget = r.soloBianco
            ? Color(red: Luce.rgbBianco(temperatura: r.temperatura).r, green: Luce.rgbBianco(temperatura: r.temperatura).g, blue: Luce.rgbBianco(temperatura: r.temperatura).b)
            : Color(hue: r.tonalita, saturation: r.saturazione, brightness: 1.0)

        ZStack {
            SfondoAurora(luci: gestore.luci)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CartaVetro(tinta: coloreTarget.opacity(r.attiva ? 0.16 : 0.06), raggio: 26, padding: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Routine Sveglia")
                                    .font(.headline)
                                Text("Crescendo progressivo per tutte le luci")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { r.attiva },
                                set: { v in
                                    var mod = r
                                    mod.attiva = v
                                    gestore.salvaRoutineSveglia(mod)
                                }
                            ))
                            .labelsHidden()
                        }

                        Divider()

                        HStack {
                            Label("Orario sveglia", systemImage: "alarm.fill")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            DatePicker("", selection: dataSvegliaBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }

                        // Riepilogo curva temporale (es. 06:37 -> 10%, 06:40 -> 80%, 06:41 -> 100%)
                        HStack(spacing: 8) {
                            tappaTimeline(ora: orarioSfasato(minutiDelta: -r.minutiPrima), etichetta: "Inizio 10%", tinta: coloreTarget.opacity(0.65))
                            tappaTimeline(ora: r.orarioFormattato, etichetta: "Sveglia \(Int((r.livelloSveglia * 100).rounded()))%", tinta: coloreTarget)
                            tappaTimeline(ora: orarioSfasato(minutiDelta: 1), etichetta: "+1m \(Int((r.livelloDopoMinuto * 100).rounded()))%", tinta: coloreTarget)
                        }
                    }

                    CartaVetro(raggio: 24, padding: 18) {
                        HStack {
                            Text("Colore al risveglio")
                                .font(.headline)
                            Spacer()
                            Picker("Tipo luce", selection: Binding(
                                get: { r.soloBianco },
                                set: { v in
                                    var mod = r
                                    mod.soloBianco = v
                                    gestore.salvaRoutineSveglia(mod)
                                }
                            )) {
                                Text("Colore").tag(false)
                                Text("Bianco").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 165)
                        }

                        if r.soloBianco {
                            SelettoreBiancoVetro(
                                temperatura: Binding(
                                    get: { r.temperatura },
                                    set: { v in
                                        var mod = gestore.routineSveglia
                                        mod.temperatura = v
                                        gestore.salvaRoutineSveglia(mod)
                                    }
                                ),
                                kelvin: Int((2700.0 + r.temperatura * 3800.0).rounded())
                            ) { _ in }
                        } else {
                            DiscoColoreVetro(
                                tonalita: Binding(
                                    get: { r.tonalita },
                                    set: { h in
                                        var mod = gestore.routineSveglia
                                        mod.tonalita = h
                                        gestore.salvaRoutineSveglia(mod)
                                    }
                                ),
                                saturazione: Binding(
                                    get: { r.saturazione },
                                    set: { s in
                                        var mod = gestore.routineSveglia
                                        mod.saturazione = s
                                        gestore.salvaRoutineSveglia(mod)
                                    }
                                ),
                                coloriSalvati: gestore.coloriSalvati,
                                alPreset: {
                                    let mod = gestore.routineSveglia
                                    gestore.salvaRoutineSveglia(mod)
                                },
                                applicaSalvato: { salvato in
                                    var mod = gestore.routineSveglia
                                    mod.tonalita = salvato.tonalita
                                    mod.saturazione = salvato.saturazione
                                    gestore.salvaRoutineSveglia(mod)
                                },
                                salvaColore: {
                                    gestore.salvaColoreCorrente(tonalita: r.tonalita, saturazione: r.saturazione, luminosita: 1.0)
                                },
                                eliminaColore: { idColore in
                                    gestore.eliminaColoreSalvato(id: idColore)
                                }
                            ) { _ in }
                        }
                    }

                    CartaVetro(raggio: 24, padding: 18) {
                        Text("Curva del crescendo")
                            .font(.headline)

                        Stepper(value: Binding(
                            get: { r.minutiPrima },
                            set: { v in
                                var mod = r
                                mod.minutiPrima = v
                                gestore.salvaRoutineSveglia(mod)
                            }
                        ), in: 1...10) {
                            HStack {
                                Text("Anticipo prima della sveglia")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(r.minutiPrima) min")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }

                        Stepper(value: Binding(
                            get: { Int((r.livelloSveglia * 100).rounded()) },
                            set: { perc in
                                var mod = r
                                mod.livelloSveglia = Double(perc) / 100.0
                                gestore.salvaRoutineSveglia(mod)
                            }
                        ), in: 30...100, step: 5) {
                            HStack {
                                Text("Intensità all'ora della sveglia")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int((r.livelloSveglia * 100).rounded()))%")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }

                        if !gestore.progressoCrescendo.isEmpty {
                            HStack(spacing: 8) {
                                if gestore.crescendoInCorso {
                                    ProgressView()
                                }
                                Text(gestore.progressoCrescendo)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }

                        HStack(spacing: 10) {
                            Button {
                                if gestore.crescendoInCorso {
                                    gestore.fermaCrescendoSveglia()
                                } else {
                                    gestore.avviaCrescendoSveglia(rapidoDemo: true)
                                }
                            } label: {
                                Label(
                                    gestore.crescendoInCorso ? "Ferma" : "Testa crescendo (10s)",
                                    systemImage: gestore.crescendoInCorso ? "stop.fill" : "play.fill"
                                )
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(gestore.crescendoInCorso ? .pericoloDomus : coloreTarget)

                            if !gestore.crescendoInCorso {
                                Button {
                                    gestore.avviaCrescendoSveglia(rapidoDemo: false)
                                } label: {
                                    Text("Avvia \(r.minutiPrima)m")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        .padding(.top, 4)
                    }

                    CartaVetro(raggio: 24, padding: 18) {
                        DisclosureGroup(isExpanded: $mostraGuidaOrologio) {
                            VStack(alignment: .leading, spacing: 10) {
                                Divider().padding(.top, 4)
                                Text("Apple isola per privacy le sveglie dell'app **Orologio**: nessuna app esterna (neanche con `AlarmKit` di iOS 26/27) può leggere la tua sveglia delle 06:40 di nascosto.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Per far partire automaticamente il crescendo anche se cambi sveglia ogni giorno, Domus espone due azioni native in **Comandi Rapidi**:")
                                    .font(.caption.weight(.semibold))

                                Text("1. Apri **Comandi Rapidi** su iPhone → scheda **Automazione** → **+**.\n2. Scegli **Sveglia** (es. *Quando suona* oppure all'ora di *Andare a dormire* per leggere l'orario del giorno dopo con **Trova sveglie** → **Sincronizza orario sveglia Domus**).\n3. Come azione scegli **Avvia crescendo sveglia Domus** e imposta *Esegui immediatamente*: partirà a schermo spento sia via Wi-Fi LAN che Cloud.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Label("Collega alla sveglia dell'Orologio Apple", systemImage: "iphone.radiowaves.left.and.right")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
        }
        .navigationTitle("Routine")
    }

    private func tappaTimeline(ora: String, etichetta: String, tinta: Color) -> some View {
        VStack(spacing: 3) {
            Text(ora)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(etichetta)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(tinta.opacity(0.20)), in: .rect(cornerRadius: 14))
    }
}
