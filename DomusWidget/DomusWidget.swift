import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct DomusWidgets: WidgetBundle {
    var body: some Widget {
        WidgetLuciCasa()
        WidgetBloccoCasa()
        ControlloRapidoLuci()
    }
}

struct FornitoreDomus: TimelineProvider {
    func placeholder(in context: Context) -> VoceWidgetDomus {
        VoceWidgetDomus(date: Date(), luci: ArchivioCondiviso.esempi)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoceWidgetDomus) -> Void) {
        let salvate = ArchivioCondiviso.caricaLuci()
        completion(VoceWidgetDomus(date: Date(), luci: salvate.isEmpty ? ArchivioCondiviso.esempi : salvate))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoceWidgetDomus>) -> Void) {
        let luci = ArchivioCondiviso.caricaLuci()
        let adesso = Date()
        let voce = VoceWidgetDomus(date: adesso, luci: luci)
        completion(Timeline(entries: [voce], policy: .after(adesso.addingTimeInterval(20 * 60))))
    }
}

struct WidgetLuciCasa: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "domus.luci", provider: FornitoreDomus()) { voce in
            VistaWidgetLuci(voce: voce)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Luci & Strisce LED")
        .description("Accendi o spegni al volo le tue lampadine e strisce Tuya e Magic Home.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetBloccoCasa: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "domus.blocco", provider: FornitoreDomus()) { voce in
            VistaBloccoLuci(voce: voce)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Stato Luci")
        .description("Mostra quante luci sono accese sulla schermata di blocco.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

/// Pulsante nativo per il Centro di Controllo e i tasti rapidi della schermata di blocco.
struct ControlloRapidoLuci: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "domus.controllo.tutte") {
            ControlWidgetButton(action: CommutaTutteLuciIntent()) {
                Label("Luci Domus", systemImage: "lightbulb.led.fill")
            }
        }
        .displayName("Commuta Luci Domus")
    }
}
