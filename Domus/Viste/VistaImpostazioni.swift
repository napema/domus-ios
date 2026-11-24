import SwiftUI
import UIKit

struct VistaImpostazioni: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @AppStorage("aspettoDomus") private var aspetto = "dark"
    @State private var credenziali = CredenzialiTuya()
    @State private var foglioImportJSON = false
    @State private var jsonDaImportare = ""

    var body: some View {
        let wifi = ReteLocale.infoWiFi()
        let totTuya = gestore.luci.filter { $0.marca == .tuya }.count
        let totMagic = gestore.luci.filter { $0.marca == .magicHome }.count
        let totLAN = gestore.luci.filter(\.viaLocale).count

        ZStack {
            SfondoAurora(luci: gestore.luci)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CartaVetro {
                        Label("Stato rete e protocolli", systemImage: "network")
                            .font(.headline)

                        riga(etichetta: "Wi-Fi iPhone", valore: wifi?.ipLocale ?? "Non connesso al Wi-Fi")
                        riga(etichetta: "Dispositivi Magic Home (TCP 5577)", valore: "\(totMagic)")
                        riga(etichetta: "Dispositivi Tuya (LAN 6668 + Cloud)", valore: "\(totTuya)")
                        riga(etichetta: "Controllo diretto in LAN", valore: "\(totLAN) su \(gestore.luci.count)")

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    let n = await gestore.scansionaReteWiFi()
                                    gestore.mostraAvviso(n > 0 ? "Aggiornate \(n) luci in Wi-Fi" : "Scansione completata")
                                }
                            } label: {
                                Label("Riscansiona LAN", systemImage: "wifi")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .disabled(gestore.scansioneInCorso)

                            if gestore.credenzialiTuya.configurate {
                                Button {
                                    Task { await gestore.sincronizzaTuyaCloud() }
                                } label: {
                                    Label("Sincronizza Tuya", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.footnote.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(.tuyaDomus)
                                .disabled(gestore.sincronizzazioneTuyaInCorso)
                            }
                        }
                        .padding(.top, 4)
                    }

                    CartaVetro {
                        Label("Aspetto Liquid Glass", systemImage: "sparkles.rectangle.stack.fill")
                            .font(.headline)

                        Picker("Tema", selection: $aspetto) {
                            Text("Scuro").tag("dark")
                            Text("Chiaro").tag("light")
                            Text("Sistema").tag("sistema")
                        }
                        .pickerStyle(.segmented)
                    }

                    CartaVetro {
                        Label("Credenziali Tuya Cloud", systemImage: "key.fill")
                            .font(.headline)

                        Picker("Regione", selection: $credenziali.regione) {
                            ForEach(RegioneTuya.allCases) { r in
                                Text(r.etichetta).tag(r)
                            }
                        }
                        .font(.subheadline)

                        TextField("Access ID", text: $credenziali.accessId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                        SecureField("Access Secret", text: $credenziali.accessSecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                        Button {
                            gestore.salvaCredenziali(credenziali)
                            gestore.mostraAvviso("Credenziali Tuya salvate")
                        } label: {
                            Text("Salva credenziali")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                    }

                    CartaVetro {
                        Label("Backup e importazione JSON (anche TinyTuya)", systemImage: "externaldrive.fill.badge.timemachine")
                            .font(.headline)

                        Text("Puoi copiare il backup JSON completo delle tue luci (incluse `local_key` e IP) o incollare direttamente un file `devices.json` generato da TinyTuya.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.string = gestore.esportaJSON()
                                gestore.mostraAvviso("Backup JSON copiato negli appunti")
                            } label: {
                                Label("Copia JSON", systemImage: "doc.on.doc")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)

                            Button {
                                jsonDaImportare = UIPasteboard.general.string ?? ""
                                foglioImportJSON = true
                            } label: {
                                Label("Importa JSON", systemImage: "square.and.arrow.down")
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                    }

                    CartaVetro {
                        Label("Widget Home, Blocco e Centro di Controllo", systemImage: "square.grid.2x2.fill")
                            .font(.headline)
                        Text("Tieni premuto sulla schermata Home o sulla schermata di blocco e cerca **Domus**: puoi commutare singole luci o spegnere tutta la casa senza aprire l'app. Se durante l'installazione su SideStore usi `Domus-senza-widget.ipa`, l'app funziona identica senza l'estensione widget.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Impostazioni")
        .onAppear {
            credenziali = gestore.credenzialiTuya
        }
        .sheet(isPresented: $foglioImportJSON) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Incolla qui il JSON di Domus oppure `devices.json` di TinyTuya:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $jsonDaImportare)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(8)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(16)
                .navigationTitle("Importa JSON")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { foglioImportJSON = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Importa") {
                            let n = gestore.importaDaJSON(jsonDaImportare)
                            foglioImportJSON = false
                            gestore.mostraAvviso(n > 0 ? "Importati \(n) dispositivi" : "Formato JSON non riconosciuto", errore: n == 0)
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func riga(etichetta: String, valore: String) -> some View {
        HStack {
            Text(etichetta)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(valore)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
    }
}
