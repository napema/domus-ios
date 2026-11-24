import SwiftUI

struct VistaAggiungi: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @Environment(\.dismiss) private var chiudi

    @State private var sezione = "wifi"
    @State private var credenziali = CredenzialiTuya()

    // Campi inserimento manuale
    @State private var marcaManuale: MarcaLuce = .magicHome
    @State private var tipoManuale: TipoLuce = .striscia
    @State private var nomeManuale = ""
    @State private var stanzaManuale = "Salotto"
    @State private var ipManuale = ""
    @State private var tuyaIdManuale = ""
    @State private var localKeyManuale = ""
    @State private var versioneManuale = "3.4"
    @State private var varianteManuale: VarianteMagicHome = .rgbw

    var body: some View {
        NavigationStack {
            ZStack {
                SfondoAurora(luci: gestore.luci)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Picker("Metodo", selection: $sezione) {
                            Text("Wi-Fi automatico").tag("wifi")
                            Text("Tuya Cloud").tag("tuya")
                            Text("Manuale").tag("manuale")
                        }
                        .pickerStyle(.segmented)

                        switch sezione {
                        case "wifi":
                            pannelloScansioneWiFi
                        case "tuya":
                            pannelloTuyaCloud
                        default:
                            pannelloManuale
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Aggiungi luci")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { chiudi() }
                }
            }
            .onAppear {
                credenziali = gestore.credenzialiTuya
            }
        }
    }

    // MARK: - 1. Scansione automatica Wi-Fi

    private var pannelloScansioneWiFi: some View {
        CartaVetro(tinta: Color.cianoDomus.opacity(0.14), raggio: 26, padding: 20) {
            Label("Scoperta diretta sulla tua rete Wi-Fi", systemImage: "wifi.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.cianoDomus)

            if let wifi = ReteLocale.infoWiFi() {
                Text("iPhone connesso su **\(wifi.ipLocale)** · sottorete `\(wifi.prefissoSottorete).1–254`.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Assicurati che l'iPhone sia collegato al Wi-Fi di casa (2.4 / 5 GHz sulla stessa rete delle luci).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("• Trova automaticamente tutte le lampadine e strisce **Magic Home (魔法家)** sulla porta TCP `5577` e UDP `48899`.\n• Abbina automaticamente l'indirizzo IP locale alle luci **Tuya** già importate sulla porta `6668`.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !gestore.statoScansione.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(gestore.statoScansione)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    let n = await gestore.scansionaReteWiFi()
                    gestore.mostraAvviso(n > 0 ? "Trovate o aggiornate \(n) luci!" : "Nessun nuovo dispositivo trovato sulla sottorete")
                    if n > 0 { chiudi() }
                }
            } label: {
                Label(gestore.scansioneInCorso ? "Scansione in corso…" : "Avvia scansione Wi-Fi", systemImage: "dot.radiowaves.left.and.right")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(gestore.scansioneInCorso)
        }
    }

    // MARK: - 2. Collegamento Tuya Cloud + Local Key automatiche

    private var pannelloTuyaCloud: some View {
        VStack(alignment: .leading, spacing: 16) {
            CartaVetro(tinta: Color.tuyaDomus.opacity(0.14), raggio: 26, padding: 18) {
                Label("Importa da Tuya / Smart Life", systemImage: "cloud.bolt.fill")
                    .font(.headline)
                    .foregroundStyle(Color.tuyaDomus)

                Text("Inserendo **Access ID** e **Access Secret** del tuo progetto gratuito su `iot.tuya.com`, Domus scarica in automatico tutte le tue lampadine e strisce LED insieme alle loro `local_key` (per comandarle subito in LAN veloce senza latenza, e via Cloud quando sei fuori casa).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Data Center", selection: $credenziali.regione) {
                    ForEach(RegioneTuya.allCases) { reg in
                        Text(reg.etichetta).tag(reg)
                    }
                }
                .font(.subheadline)

                campo(titolo: "Access ID / Client ID", testo: $credenziali.accessId, segreto: false)
                campo(titolo: "Access Secret / Client Secret", testo: $credenziali.accessSecret, segreto: true)
                campo(titolo: "UID App Account (facoltativo)", testo: $credenziali.uidUtente, segreto: false)

                Button {
                    gestore.salvaCredenziali(credenziali)
                    Task {
                        await gestore.sincronizzaTuyaCloud()
                        if !gestore.luci.filter({ $0.marca == .tuya }).isEmpty {
                            chiudi()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if gestore.sincronizzazioneTuyaInCorso {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(gestore.sincronizzazioneTuyaInCorso ? "Sincronizzazione…" : "Salva e importa tutte le luci Tuya")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.tuyaDomus)
                .disabled(!credenziali.configurate || gestore.sincronizzazioneTuyaInCorso)
            }

            CartaVetro(raggio: 22, padding: 16) {
                Text("Promemoria rapido iot.tuya.com (2 minuti, gratis)")
                    .font(.footnote.weight(.semibold))
                Text("1. Su **iot.tuya.com** apri *Cloud → Development → Create Cloud Project* (Data Center: *Central Europe*).\n2. Abilita le API *IoT Core* e *Authorization Token Management*.\n3. Nella scheda *Devices → Link Tuya App Account*, scansiona il QR dall'app Tuya o Smart Life sul telefono.\n4. Copia *Access ID* e *Access Secret* da *Overview* qui sopra.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 3. Inserimento manuale

    private var pannelloManuale: some View {
        CartaVetro(raggio: 26, padding: 18) {
            Text("Aggiungi dispositivo manualmente")
                .font(.headline)

            Picker("Ecosistema", selection: $marcaManuale) {
                ForEach(MarcaLuce.allCases) { m in
                    Text(m.etichetta).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Picker("Formato", selection: $tipoManuale) {
                ForEach(TipoLuce.allCases) { t in
                    Text(t.etichetta).tag(t)
                }
            }
            .pickerStyle(.segmented)

            campo(titolo: "Nome (es. Striscia Scrivania)", testo: $nomeManuale, segreto: false)
            campo(titolo: "Stanza (es. Studio)", testo: $stanzaManuale, segreto: false)
            campo(titolo: "Indirizzo IP locale (es. 192.168.1.55)", testo: $ipManuale, segreto: false, tastiera: .numbersAndPunctuation)

            if marcaManuale == .magicHome {
                Picker("Variante controller", selection: $varianteManuale) {
                    ForEach(VarianteMagicHome.allCases) { v in
                        Text(v.descrizione).tag(v)
                    }
                }
                .font(.subheadline)
            } else {
                campo(titolo: "Tuya Device ID", testo: $tuyaIdManuale, segreto: false)
                campo(titolo: "Local Key (16 caratteri)", testo: $localKeyManuale, segreto: false)
                Picker("Versione protocollo LAN", selection: $versioneManuale) {
                    Text("3.3").tag("3.3")
                    Text("3.4").tag("3.4")
                    Text("3.5").tag("3.5")
                }
                .pickerStyle(.segmented)
            }

            let puoSalvare = !nomeManuale.trimmingCharacters(in: .whitespaces).isEmpty &&
                (marcaManuale == .magicHome ? !ipManuale.trimmingCharacters(in: .whitespaces).isEmpty : !tuyaIdManuale.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                let ipPulito = ipManuale.trimmingCharacters(in: .whitespacesAndNewlines)
                let devPulito = tuyaIdManuale.trimmingCharacters(in: .whitespacesAndNewlines)
                let keyPulita = localKeyManuale.trimmingCharacters(in: .whitespacesAndNewlines)

                let nuova = Luce(
                    id: marcaManuale == .magicHome ? "mh-\(UUID().uuidString.prefix(8))" : "tuya-\(devPulito)",
                    nome: nomeManuale.trimmingCharacters(in: .whitespacesAndNewlines),
                    stanza: stanzaManuale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Casa" : stanzaManuale.trimmingCharacters(in: .whitespacesAndNewlines),
                    marca: marcaManuale,
                    tipo: tipoManuale,
                    ip: ipPulito.isEmpty ? nil : ipPulito,
                    porta: marcaManuale == .magicHome ? 5577 : 6668,
                    tuyaId: marcaManuale == .tuya ? devPulito : nil,
                    localKey: (marcaManuale == .tuya && !keyPulita.isEmpty) ? keyPulita : nil,
                    versioneProtocollo: versioneManuale,
                    varianteMagic: varianteManuale,
                    viaLocale: !ipPulito.isEmpty
                )
                gestore.aggiungiOModifica(nuova)
                gestore.mostraAvviso("\(nuova.nome) aggiunta")
                chiudi()
            } label: {
                Label("Aggiungi a Domus", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(!puoSalvare)
        }
    }

    private func campo(titolo: String, testo: Binding<String>, segreto: Bool, tastiera: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if segreto {
                    SecureField(titolo, text: testo)
                } else {
                    TextField(titolo, text: testo)
                        .keyboardType(tastiera)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
