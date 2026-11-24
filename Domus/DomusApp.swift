import Combine
import SwiftUI
import WidgetKit

@main
struct DomusApp: App {
    @Environment(\.scenePhase) private var fase
    @StateObject private var gestore = GestoreLuci.s
    @AppStorage("aspettoDomus") private var aspetto = "dark"

    var body: some Scene {
        WindowGroup {
            RadiceDomus()
                .environmentObject(gestore)
                .preferredColorScheme(aspetto == "light" ? .light : aspetto == "sistema" ? nil : .dark)
                .tint(.accentoDomus)
                .onOpenURL { url in
                    apriCollegamento(url)
                }
                .onAppear {
                    LinkDomus.gestore = { url in apriCollegamento(url) }
                    if let pendente = LinkDomus.prendiInAttesa() {
                        apriCollegamento(pendente)
                    }
                }
        }
        .onChange(of: fase) { _, nuova in
            switch nuova {
            case .active:
                if let pendente = LinkDomus.prendiInAttesa() {
                    apriCollegamento(pendente)
                }
                gestore.controllaSvegliaProgrammata()
                Task { await gestore.aggiornaStatiDaRete() }
            case .background:
                gestore.salva()
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
    }

    private func apriCollegamento(_ url: URL) {
        guard url.scheme == "domus" else { return }
        let parti = url.pathComponents.filter { $0 != "/" }
        switch url.host() ?? "" {
        case "aggiungi":
            gestore.mostraAggiungi = true
        case "routine-avvia":
            gestore.avviaCrescendoSveglia(rapidoDemo: false)
        case "luce":
            if let id = parti.first {
                gestore.luceApertaID = id
            }
        default:
            break
        }
    }
}

struct RadiceDomus: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @State private var scheda = "luci"
    @State private var testoRicerca = ""

    var body: some View {
        let accese = gestore.acceseCount
        TabView(selection: $scheda) {
            Tab("Luci", systemImage: "lightbulb.led.fill", value: "luci") {
                NavigationStack {
                    VistaLuci()
                }
            }
            Tab("Strisce", systemImage: "light.strip.2", value: "strisce") {
                NavigationStack {
                    VistaStrisce()
                }
            }
            Tab("Routine", systemImage: "alarm.fill", value: "routine") {
                NavigationStack {
                    VistaRoutine()
                }
            }
            Tab("Impostazioni", systemImage: "gearshape.fill", value: "impostazioni") {
                NavigationStack {
                    VistaImpostazioni()
                }
            }
            Tab(value: "cerca", role: .search) {
                NavigationStack {
                    VistaRicercaLuci(testo: $testoRicerca)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            gestore.controllaSvegliaProgrammata()
        }
        .tabViewBottomAccessory(isEnabled: !gestore.luci.isEmpty) {
            BarraStatoRapida(accese: accese, totale: gestore.luci.count) {
                gestore.impostaTutte(accese: accese == 0)
            }
        }
        .overlay(alignment: .top) {
            if let avviso = gestore.avviso {
                BannerVetro(avviso: avviso)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $gestore.mostraAggiungi) {
            VistaAggiungi()
                .environmentObject(gestore)
        }
        .sheet(
            isPresented: Binding(
                get: { gestore.luceApertaID != nil },
                set: { if !$0 { gestore.luceApertaID = nil } }
            )
        ) {
            if let id = gestore.luceApertaID {
                DettaglioLuce(idLuce: id)
                    .environmentObject(gestore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct BarraStatoRapida: View {
    let accese: Int
    let totale: Int
    let azione: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accese > 0 ? Color.accentoDomus : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
                .shadow(color: accese > 0 ? Color.accentoDomus.opacity(0.8) : .clear, radius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(accese == 0 ? "Tutte le luci spente" : accese == 1 ? "1 luce accesa su \(totale)" : "\(accese) luci accese su \(totale)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(accese == 0 ? "Tocca per accendere tutto" : "Tocca per spegnere tutto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: accese > 0 ? "power.circle.fill" : "power.circle")
                .font(.title3)
                .foregroundStyle(accese > 0 ? Color.accentoDomus : .secondary)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: azione)
    }
}

private struct BannerVetro: View {
    let avviso: GestoreLuci.Avviso

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: avviso.errore ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(avviso.errore ? Color.pericoloDomus : Color.successoDomus)
            Text(avviso.testo)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint((avviso.errore ? Color.pericoloDomus : Color.successoDomus).opacity(0.16)), in: .capsule)
        .padding(.horizontal, 16)
    }
}

struct VistaRicercaLuci: View {
    @EnvironmentObject private var gestore: GestoreLuci
    @Binding var testo: String

    private var filtrate: [Luce] {
        let q = testo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return gestore.luci }
        return gestore.luci.filter {
            $0.nome.lowercased().contains(q) ||
            $0.stanza.lowercased().contains(q) ||
            $0.marca.etichetta.lowercased().contains(q) ||
            ($0.ip ?? "").contains(q)
        }
    }

    var body: some View {
        ZStack {
            SfondoAurora(luci: gestore.luci)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filtrate) { luce in
                        TesseraLuceVetro(luce: luce)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Cerca")
        .searchable(text: $testo, prompt: "Lampadina, striscia, stanza o IP")
    }
}
