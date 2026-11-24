import SwiftUI
import UIKit

extension Color {
    static let accentoDomus = Color(esadecimale: "#FFB02E")
    static let cianoDomus = Color(esadecimale: "#38B6FF")
    static let tuyaDomus = Color(esadecimale: "#FF6B2C")
    static let pericoloDomus = Color(esadecimale: "#FF453A")
    static let successoDomus = Color(esadecimale: "#32D74B")
    static let secondarioDomus = Color(uiColor: .secondaryLabel)
}

func toccoLeggero() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

func toccoSelezione() {
    UISelectionFeedbackGenerator().selectionChanged()
}

/// Sfondo vivo reattivo per Liquid Glass: proietta aloni morbidi coi colori reali delle luci accese,
/// così i pannelli `.glassEffect` rifrangono l'illuminazione attuale della casa.
struct SfondoAurora: View {
    let luci: [Luce]
    @Environment(\.colorScheme) private var schema

    private var coloriAttivi: [Color] {
        let accese = luci.filter(\.accensione).prefix(3).map(\.coloreVisivo)
        if accese.isEmpty {
            return [Color(esadecimale: "#243B6B").opacity(0.35), Color(esadecimale: "#3A2352").opacity(0.28)]
        }
        return Array(accese)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                (schema == .dark ? Color(red: 0.045, green: 0.05, blue: 0.085) : Color(uiColor: .systemGroupedBackground))

                ForEach(Array(coloriAttivi.enumerated()), id: \.offset) { idx, colore in
                    Circle()
                        .fill(colore.opacity(schema == .dark ? 0.30 : 0.20))
                        .frame(width: geo.size.width * 0.92, height: geo.size.width * 0.92)
                        .blur(radius: 90)
                        .offset(
                            x: idx == 0 ? -geo.size.width * 0.24 : (idx == 1 ? geo.size.width * 0.28 : 0),
                            y: idx == 0 ? -geo.size.height * 0.22 : (idx == 1 ? geo.size.height * 0.06 : geo.size.height * 0.32)
                        )
                }
            }
            .animation(.easeInOut(duration: 0.55), value: luci.map { "\($0.id):\($0.accensione):\($0.modo.rawValue):\($0.tonalita):\($0.temperatura)" })
        }
        .ignoresSafeArea()
    }
}

/// Contenitore Liquid Glass arrotondato per raggruppare controlli e schede informative.
struct CartaVetro<Contenuto: View>: View {
    var tinta: Color? = nil
    var raggio: CGFloat = 24
    var padding: CGFloat = 16
    @ViewBuilder var contenuto: () -> Contenuto

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            contenuto()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tinta), in: .rect(cornerRadius: raggio))
    }
}

/// Pillola filtro in stile Liquid Glass (stanze, marche, modalità).
struct PillolaVetro: View {
    let titolo: String
    var icona: String? = nil
    var attiva: Bool
    var tinta: Color = .accentoDomus
    let azione: () -> Void

    var body: some View {
        Button {
            toccoSelezione()
            azione()
        } label: {
            HStack(spacing: 6) {
                if let icona {
                    Image(systemName: icona)
                        .font(.caption.weight(.semibold))
                }
                Text(titolo)
                    .font(.subheadline.weight(attiva ? .semibold : .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(attiva ? Color.primary : Color.secondarioDomus)
            .glassEffect(
                attiva ? .regular.tint(tinta.opacity(0.38)).interactive() : .regular.interactive(),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
    }
}

/// Badge compatto per indicare Tuya / Magic Home e stato LAN / Cloud.
struct EtichettaProtocollo: View {
    let luce: Luce

    var body: some View {
        HStack(spacing: 5) {
            Text(luce.marca.etichetta)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(esadecimale: luce.marca.coloreHex))

            Text("·")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Image(systemName: luce.viaLocale ? "bolt.horizontal.fill" : "cloud.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(luce.viaLocale ? Color.successoDomus : Color.cianoDomus)

            Text(luce.viaLocale ? "LAN" : "Cloud")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Slider tattile largo in Liquid Glass per regolare luminosità o velocità effetto con trascinamento continuo.
struct BarraTattileVetro: View {
    let titolo: String
    let simbolo: String
    @Binding var valore: Double
    var minimo: Double = 0.01
    var coloreBarra: Color = .accentoDomus
    var testoDestra: String? = nil
    var alRilascio: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(titolo, systemImage: simbolo)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(testoDestra ?? "\(Int((valore * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let larghezza = max(1, geo.size.width)
                let frazione = CGFloat(min(1, max(0, (valore - minimo) / (1.0 - minimo))))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.07))

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [coloreBarra.opacity(0.55), coloreBarra],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(22, larghezza * frazione))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let raw = Double(min(1, max(0, g.location.x / larghezza)))
                            let nuovo = minimo + raw * (1.0 - minimo)
                            if (nuovo > 0.99 && valore <= 0.99) || (nuovo < minimo + 0.01 && valore >= minimo + 0.01) {
                                toccoLeggero()
                            }
                            valore = nuovo
                        }
                        .onEnded { _ in
                            alRilascio?()
                        }
                )
            }
            .frame(height: 46)
        }
    }
}

/// Selettore continuo della temperatura del bianco da 2700K (ambra calda) a 6500K (luce diurna fredda).
struct SelettoreBiancoVetro: View {
    @Binding var temperatura: Double
    let kelvin: Int
    var alCambio: (Bool) -> Void

    private let predefiniti: [(nome: String, temp: Double, k: String)] = [
        ("Candela", 0.0, "2700K"),
        ("Calda", 0.25, "3650K"),
        ("Naturale", 0.52, "4700K"),
        ("Giorno", 1.0, "6500K"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Temperatura bianco", systemImage: "thermometer.sun.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(kelvin) K")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let larghezza = max(1, geo.size.width)
                let x = larghezza * CGFloat(min(1, max(0, temperatura)))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.68, blue: 0.28),
                                    Color(red: 1.0, green: 0.91, blue: 0.78),
                                    Color(red: 0.80, green: 0.91, blue: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 36)

                    Circle()
                        .fill(.white)
                        .frame(width: 30, height: 30)
                        .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
                        .offset(x: min(max(3, x - 15), larghezza - 33))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            temperatura = Double(min(1, max(0, g.location.x / larghezza)))
                            alCambio(false)
                        }
                        .onEnded { _ in
                            toccoLeggero()
                            alCambio(true)
                        }
                )
            }
            .frame(height: 36)

            HStack(spacing: 8) {
                ForEach(predefiniti, id: \.nome) { voce in
                    let vicina = abs(temperatura - voce.temp) < 0.09
                    Button {
                        toccoSelezione()
                        temperatura = voce.temp
                        alCambio(true)
                    } label: {
                        VStack(spacing: 2) {
                            Text(voce.nome).font(.caption.weight(.semibold))
                            Text(voce.k).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .glassEffect(
                            vicina ? .regular.tint(Color.accentoDomus.opacity(0.32)).interactive() : .regular.interactive(),
                            in: .rect(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Ruota cromatica HSB interattiva + tavolozza colori rapidi per lampadine e strisce LED.
struct DiscoColoreVetro: View {
    @Binding var tonalita: Double
    @Binding var saturazione: Double
    var alCambio: (Bool) -> Void

    private let coloriRapidi: [(Double, Double)] = [
        (0.02, 0.90), // Rosso corallo
        (0.08, 0.88), // Ambra
        (0.15, 0.85), // Oro
        (0.35, 0.85), // Smeraldo
        (0.53, 0.88), // Ciano
        (0.64, 0.90), // Blu notte
        (0.77, 0.86), // Viola neon
        (0.90, 0.84), // Magenta
    ]

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let lato = min(geo.size.width, 230)
                let raggio = lato / 2.0
                let angolo = tonalita * 2.0 * .pi
                let dist = saturazione * (raggio - 16)
                let px = raggio + CGFloat(cos(angolo) * dist)
                let py = raggio + CGFloat(sin(angolo) * dist)

                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: (0...12).map {
                                    Color(hue: Double($0) / 12.0, saturation: 1.0, brightness: 1.0)
                                }),
                                center: .center
                            )
                        )
                        .overlay {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.white, .white.opacity(0)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: raggio
                                    )
                                )
                        }
                        .frame(width: lato, height: lato)
                        .shadow(color: Color(hue: tonalita, saturation: saturazione, brightness: 1).opacity(0.38), radius: 22)

                    Circle()
                        .fill(Color(hue: tonalita, saturation: saturazione, brightness: 1.0))
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .frame(width: 30, height: 30)
                        .position(x: px + (geo.size.width - lato) / 2.0, y: py)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let cx = geo.size.width / 2.0
                            let cy = lato / 2.0
                            let dx = Double(g.location.x - cx)
                            let dy = Double(g.location.y - cy)
                            var ang = atan2(dy, dx) / (2.0 * .pi)
                            if ang < 0 { ang += 1.0 }
                            tonalita = min(1, max(0, ang))
                            saturazione = min(1, max(0, hypot(dx, dy) / Double(raggio - 16)))
                            alCambio(false)
                        }
                        .onEnded { _ in
                            toccoLeggero()
                            alCambio(true)
                        }
                )
            }
            .frame(height: 234)

            HStack(spacing: 10) {
                ForEach(Array(coloriRapidi.enumerated()), id: \.offset) { _, coppia in
                    let attivo = abs(tonalita - coppia.0) < 0.04 && saturazione > 0.6
                    Button {
                        toccoSelezione()
                        tonalita = coppia.0
                        saturazione = coppia.1
                        alCambio(true)
                    } label: {
                        Circle()
                            .fill(Color(hue: coppia.0, saturation: coppia.1, brightness: 1.0))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Circle().stroke(.white.opacity(attivo ? 1.0 : 0.25), lineWidth: attivo ? 2.5 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Tessera Liquid Glass per una singola lampadina o striscia LED, con accensione immediata e regolazione rapida luminosità.
struct TesseraLuceVetro: View {
    @EnvironmentObject private var gestore: GestoreLuci
    let luce: Luce

    var body: some View {
        let colore = luce.coloreVisivo

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(luce.accensione ? colore.opacity(0.28) : Color.primary.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: luce.tipo.simbolo)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(luce.accensione ? colore : .secondary)
                        .shadow(color: luce.accensione ? colore.opacity(0.7) : .clear, radius: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(luce.nome)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(luce.stanza)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        EtichettaProtocollo(luce: luce)
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    gestore.commuta(luce.id)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(luce.accensione ? Color.black : Color.primary)
                        .background(
                            luce.accensione ? colore : Color.primary.opacity(0.10),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }

            if luce.accensione {
                GeometryReader { geo in
                    let w = max(1, geo.size.width)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [colore.opacity(0.55), colore],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(18, w * CGFloat(luce.luminosita)))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { g in
                                var mod = luce
                                mod.luminosita = Double(min(1, max(0.02, g.location.x / w)))
                                gestore.aggiorna(mod, immediato: false)
                            }
                            .onEnded { g in
                                toccoLeggero()
                                var mod = luce
                                mod.luminosita = Double(min(1, max(0.02, g.location.x / w)))
                                gestore.aggiorna(mod, immediato: true)
                            }
                    )
                }
                .frame(height: 10)
            }
        }
        .padding(16)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            toccoLeggero()
            gestore.luceApertaID = luce.id
        }
        .glassEffect(
            luce.accensione ? .regular.tint(colore.opacity(0.16)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 24)
        )
    }
}
