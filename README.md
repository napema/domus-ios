# Domus per iPhone (iOS 27 Liquid Glass)

App nativa in **SwiftUI** costruita con il design system **Liquid Glass** (SDK Xcode 27, compatibile da iOS 26.1 a iOS 27+) per comandare da un'unica interfaccia reattiva tutte le lampadine e le strisce LED **Tuya / Smart Life** e **Magic Home (魔法家)**.

La struttura segue fedelmente quella di `Life` (`project.yml` + `XcodeGen`, compilazione senza firma su **Codemagic** o GitHub Actions, doppio IPA con e senza estensione widget pronto per **SideStore / iLoader**).

---

## Cosa controlla

1. **Magic Home / 魔法家 (Zengge / Flux LED)**
   - **Zero account e zero cloud**: controllo istantaneo diretto sulla rete Wi-Fi locale tramite **TCP porta `5577`**.
   - **Scoperta doppia**: broadcast **UDP `48899`** (`HF-A11ASSISTHREAD`) + scansione parallela non bloccante della sottorete `/24` sulla porta `5577` (trova tutte le strisce e lampadine in ~0,8 secondi anche con Apple ID gratuito senza entitlement Multicast).
   - Supporta strisce RGBW (8 byte), lampadine RGB+CCT bianco caldo/freddo (9 byte), strisce RGB classiche, dimmer ed effetti dinamici hardware (`0x25`–`0x38`) con velocità regolabile.

2. **Tuya / Smart Life**
   - **Importazione automatica in 1 tocco** tramite **Tuya Cloud OpenAPI** (`iot.tuya.com`, Data Center Europa Centrale predefinito): scarica l'elenco completo di lampadine e strisce LED insieme alle rispettive **`local_key`**.
   - **Controllo ibrido LAN + Cloud**:
     - Quando sei sul Wi-Fi di casa parla direttamente col dispositivo sulla **porta TCP `6668`** supportando tutti i protocolli **v3.3** (`0x55AA` AES-ECB), **v3.4** (handshake 3-way HMAC-SHA256) e **v3.5** (`0x6699` AES-128-GCM).
     - Quando sei fuori casa (4G/5G), passa automaticamente alle API **Tuya Cloud** senza interruzioni.
   - Compatibile anche con l'importazione diretta di un file `devices.json` generato da `tinytuya`.

3. **Funzioni unificate e Widget**
   - **Atmosfere miste e Regia Strisce LED**: applica lo stesso colore RGB, temperatura bianco (`2700K–6500K`) o effetto contemporaneamente a luci Tuya e Magic Home.
   - **Widget interattivi** per schermata Home, schermata di blocco e pulsante per il **Centro di Controllo**.

---

## Installazione rapida su SideStore / iLoader (come Life)

Indirizzi diretti (aggiornati automaticamente a ogni push su `main`):

- **IPA completa (con widget)**: `https://github.com/napema/domus-ios/releases/download/ultima/Domus.ipa`
- **IPA senza widget**: `https://github.com/napema/domus-ios/releases/download/ultima/Domus-senza-widget.ipa`
- **Sorgente per SideStore**: `https://github.com/napema/domus-ios/releases/download/ultima/sorgente.json`

## Compilazione su Codemagic

1. Crea un repository Git (es. su GitHub) con il contenuto di questa cartella e spingilo sul branch `main`:
   ```powershell
   git init
   git add .
   git commit -m "Domus iOS 27 Liquid Glass"
   git branch -M main
   git remote add origin <URL_DEL_TUO_REPO>
   git push -u origin main
   ```
2. Su **Codemagic**, collega il repository e seleziona la configurazione **`codemagic.yaml`** (workflow **Compila Domus** su `mac_mini_m2` con `xcode: edge` / Xcode 27).
3. A fine build (circa 2–3 minuti) scarica dagli *Artifacts*:
   - **`Domus.ipa`**: versione completa con widget interattivi (in **iLoader / SideStore** scegli la registrazione separata delle estensioni App ID, come per Life).
   - **`Domus-senza-widget.ipa`**: riserva pronta se preferisci non registrare l'estensione dei widget.

---

## Collegamento rapido all'apertura

1. Apri **Domus** su iPhone e accetta il permesso **Rete locale** quando iOS lo chiede.
2. Tocca l'icona radar in alto a sinistra (**Scansiona Wi-Fi**): le lampadine e strisce **Magic Home** compaiono subito pronte all'uso.
3. Tocca **+ → Tuya Cloud**, incolla `Access ID` e `Access Secret` del tuo progetto su [iot.tuya.com](https://iot.tuya.com) (dopo aver collegato l'app Tuya/Smart Life con QR in *Devices → Link Tuya App Account*) e premi **Salva e importa tutte le luci Tuya**: Domus scaricherà tutte le luci con le `local_key` e abbinerà automaticamente i loro IP locali sulla rete Wi-Fi.
