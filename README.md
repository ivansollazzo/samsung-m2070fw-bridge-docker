# samsung-m2070fw-bridge-docker

Rende la Samsung Xpress **M2070FW** disponibile in rete come **multifunzione AirPrint**:

- **scanner AirScan/eSCL**, utilizzabile senza driver da macOS (Acquisizione Immagine,
  Anteprima), Windows 10/11 e Linux (`sane-airscan`);
- **stampante AirPrint** servita da CUPS con il driver ufficiale Samsung, in alternativa
  all'AirPrint integrato nella stampante.

Scanner e stampante vengono annunciati con lo stesso nome (default **"Samsung
SL-M2070FW"**) e lo stesso UUID, quindi macOS li mostra come un unico dispositivo.

Serve perché i driver Samsung per macOS sono solo Intel e smettono di funzionare
senza Rosetta 2.

## Come funziona

```
 Mac / PC ──eSCL (HTTP :8090) + Bonjour──▶ [ container ]  ──SANE smfp (driver Samsung)──▶ M2070FW
          ──IPP  (HTTP :631)  + Bonjour──▶  AirSane, CUPS  ──SPL, raw socket :9100───────▶
                                            avahi
```

- **SANE**, con il backend **`smfp`** del driver ufficiale Samsung (Unified Linux Driver,
  installato dal repository [SULDR](https://www.bchemnet.com/suldr/)), parla con la
  stampante in rete. Il driver trova da solo la stampante con un broadcast SNMP; il
  container pubblica solo quella con l'IP indicato in `SCANNER_IP`.
- In alternativa c'è il backend open source `xerox_mfp` (`SCAN_BACKEND=xerox_mfp`). Con
  la M2070FW però si è dimostrato instabile: scansioni a colori che falliscono e, con
  l'ADF, perfino riavvii della stampante.
- **[AirSane](https://github.com/SimulPiscator/AirSane)** prende lo scanner SANE e lo
  pubblica come scanner eSCL, annunciato via mDNS/Bonjour.
- Un piccolo watcher controlla ogni minuto se la stampante è raggiungibile. Quando torna
  online (era spenta, si è riavviata) fa ripetere la ricerca ad AirSane, senza riavviare
  il container.

- **CUPS** con il driver Samsung (filtro `rastertospl`, PPD della M2070) espone una coda
  condivisa. Riceve PDF/immagini dai client, li converte nel linguaggio della stampante e
  li manda sulla porta 9100. Viene annunciata come stampante AirPrint (`_ipp._tcp`,
  sottotipo `_universal`, URF), quindi funziona anche da iPhone e iPad.
- La stampante continua ad annunciare anche il proprio **AirPrint integrato**. Puoi usare
  l'uno o l'altro: sul Mac compaiono come due stampanti diverse.

## Requisiti

- Un host Linux **x86_64** sulla **stessa LAN/subnet** della stampante e dei client. Il
  driver Samsung esiste solo in versione binaria per Intel/AMD; su ARM servirebbe
  l'emulazione amd64 (qemu), non testata.
- Docker con il plugin Compose
- Stampante con **IP fisso** (reservation DHCP sul router)

## Installazione

```bash
git clone https://github.com/ivansollazzo/samsung-m2070fw-bridge-docker.git
cd samsung-m2070fw-bridge-docker
cp .env.example .env
nano .env                 # imposta almeno SCANNER_IP
```

### Scegli come annunciare lo scanner (mDNS)

Controlla se sull'host gira già avahi:

```bash
systemctl is-active avahi-daemon
```

- **`active`**: usa l'avahi dell'host. In `docker-compose.yml` togli il commento alla riga
  `- /run/dbus/system_bus_socket:/run/dbus/system_bus_socket`. Con `AVAHI_MODE=auto` il
  container se ne accorge da solo.
- **altro** (es. `inactive`, o il comando non esiste): non serve fare niente. Il container
  avvia il proprio avahi (`AVAHI_MODE=auto` → `internal`).

Non far girare due avahi contemporaneamente sullo stesso host (quello dell'host e quello
interno). mDNS diventa inaffidabile.

### Avvio

```bash
docker compose up -d --build
docker compose logs -f
```

Nei log dovresti vedere qualcosa come:

```
[bridge] Found: device `smfp:net;192.168.1.50' is a Samsung M2070 Series on 192.168.1.50 Scanner
[bridge] Starting AirSane on port 8090
```

## Verifica

1. **Interfaccia web:** apri `http://<ip-server>:8090/`. Ci deve essere lo scanner, e da lì
   puoi già fare una scansione di prova.
2. **macOS:** in Impostazioni di Sistema → Stampanti e Scanner → **Aggiungi stampante**
   compare "Samsung SL-M2070FW" come stampante AirPrint. Una volta aggiunta, la scheda
   **Scansiona** usa lo scanner del container. Lo scanner compare anche direttamente in
   **Acquisizione Immagine**.
3. **Da riga di comando, nel container:**
   ```bash
   docker compose exec scanbridge scanimage -L
   docker compose exec scanbridge scanimage -A                     # opzioni del backend
   docker compose exec -T scanbridge scanimage --format=png > test.png
   ```

## Uso da macOS, Windows e Linux

Scanner (eSCL) e stampante (IPP) usano protocolli standard, quindi non servono driver sui
client. In tutti i casi il client deve essere nella **stessa subnet** del server.

### macOS (e iPhone/iPad)
Impostazioni di Sistema → Stampanti e Scanner → **Aggiungi stampante** → "Samsung
SL-M2070FW". Da iPhone e iPad la stampante compare direttamente nel menu Stampa.

### Windows 10/11
- **Stampante:** Impostazioni → Bluetooth e dispositivi → Stampanti e scanner →
  **Aggiungi dispositivo**. La stampante viene trovata via mDNS e installata con il driver
  integrato "Microsoft IPP Class Driver". Se non compare, aggiungila a mano: "La stampante
  desiderata non è nell'elenco" → "Seleziona una stampante condivisa in base al nome" →
  `http://<IP-server>:631/printers/Samsung_SL-M2070FW`. Usa l'**IP** del server, non
  `nome.local`: con il nome Windows spesso fallisce.
- **Scanner:** dalla stessa pagina, **Aggiungi dispositivo** trova anche lo scanner. Poi
  cliccalo e scegli "Apri app scanner" (installa l'app Scanner di Microsoft se manca).
  Serve Windows 11, oppure Windows 10 aggiornato almeno a giugno 2022 (KB5014666).

### Linux
- **Stampante:** con CUPS e `cups-browsed` (presenti di default su Ubuntu, Fedora ecc.) la
  stampante compare da sola come stampante "driverless". Altrimenti:
  ```bash
  sudo lpadmin -p M2070FW -E -v ipp://<IP-server>:631/printers/Samsung_SL-M2070FW -m everywhere
  ```
- **Scanner:** installa `sane-airscan` (`sudo apt install sane-airscan`). In
  `/etc/sane.d/dll.conf` deve esserci la riga `airscan`, e la riga `escl` va commentata.
  Lo scanner compare in Simple Scan, XSane e `scanimage -L`.

### Android
La stampa funziona con il servizio di stampa integrato (Mopria). Per scansionare c'è l'app
**Mopria Scan**.

## Configurazione

| Variabile          | Default | Descrizione |
|--------------------|---------|-------------|
| `SCANNER_IP`       | *(obbligatoria)* | IP o hostname della stampante |
| `SCANNER_PORT`     | `9400`  | Porta di scansione in rete delle MFP Samsung |
| `SCANNER_LOCATION` | hostname | Posizione mostrata da macOS (campo `note` mDNS) |
| `LISTEN_PORT`      | `8090`  | Porta HTTP di AirSane (eSCL + web UI) |
| `WEB_INTERFACE`    | `true`  | Abilita la web UI |
| `AVAHI_MODE`       | `auto`  | `auto`, `host`, `internal`, `none` |
| `RESCAN_INTERVAL`  | `60`    | Secondi tra i controlli di raggiungibilità (`0` = off) |
| `DEVICE_NAME`      | `Samsung SL-M2070FW` | Nome Bonjour di scanner e stampante |
| `DEVICE_UUID`      | *(derivato)* | UUID comune; di default è calcolato da nome e IP, stabile tra i riavvii |
| `PRINTER_ENABLED`  | `true`  | Server di stampa CUPS |
| `PRINTER_QUEUE`    | `Samsung_SL-M2070FW` | Nome della coda CUPS |
| `PRINTER_URI`      | `socket://SCANNER_IP:9100` | Come CUPS raggiunge la stampante |
| `PRINTER_PAPER`    | `A4`    | Formato carta predefinito |
| `CUPS_PORT`        | `631`   | Porta di CUPS (deve essere libera sull'host) |
| `SCAN_GAMMA`       | `1.0`   | Gamma applicata alle scansioni (`1.0` = nessuna correzione) |
| `SCAN_BACKEND`     | `smfp`  | `smfp` (driver Samsung) o `xerox_mfp` (open source) |
| `SANE_JPEG`        | *(vuoto)* | Solo `xerox_mfp`: forza l'opzione `jpeg` (`yes`/`no`) |
| `DEBUG`            | `false` | Log dettagliati di AirSane |

Il **nome** con cui lo scanner appare ai client viene dal modello riportato da SANE (tipo "Samsung M2070 Series") e
non si può cambiare. La **posizione** sì.

Per opzioni avanzate (icona, gamma, opzioni SANE per dispositivo) copia
`config/options.conf.example` in `config/options.conf` e monta il file (vedi i commenti in
`docker-compose.yml`). Allo stesso modo `config/access.conf` limita quali IP possono usare
lo scanner. Di default è ammessa solo la sottorete locale.

## Risoluzione problemi

- **`scanner not found yet` nei log.** Controlla che la stampante sia accesa e che dal
  server risponda sulla porta 9400:
  ```bash
  nc -zv <SCANNER_IP> 9400
  ```
  Per i dettagli metti `DEBUG=true` (log di AirSane).
- **`scanner not found yet` con `smfp`.** Il driver cerca la stampante con un broadcast
  SNMP (UDP 161, community `public`): controlla che SNMP sia attivo sulla stampante
  (SyncThru Web Service → Impostazioni → Rete) e che host e stampante siano nella stessa
  subnet. Per vedere cosa trova:
  ```bash
  docker compose exec scanbridge scanimage -L
  ```
- **Con `xerox_mfp`: `Not a JPEG file: starts with 0x00 0x00`**, scanner bloccato o
  stampante che si riavvia. Sono problemi noti di quel backend con questa famiglia di
  Samsung: usa `SCAN_BACKEND=smfp`. Per sbloccare la stampante spegnila e riaccendila,
  poi `docker compose restart`.
- **Il Mac non vede lo scanner, ma la web UI funziona.** È un problema di mDNS. Verifica
  `AVAHI_MODE`, che non girino due avahi sull'host e che il firewall lasci passare UDP 5353
  e TCP 8090 e 631. Il Mac deve stare nella stessa subnet: mDNS non attraversa i router (e
  nemmeno, di solito, le VLAN separate o una Wi-Fi "ospiti").
- **Acquisizione Immagine dà "error 21345".** Problema noto di AirSane: abilita IPv6 sulla
  rete e sull'host, poi riavvia (vedi il README di AirSane).
- **Scansioni troppo scure o troppo chiare.** Regola `SCAN_GAMMA`: sotto 1 schiarisce,
  sopra 1 scurisce. Il README di AirSane suggerisce `0.555555` per macOS, ma con la
  M2070FW rende il testo grigio e slavato, per questo il default è `1.0`.
- **Stampa: `port 631 is already in use` nei log.** Sull'host gira già CUPS. Fermalo
  (`sudo systemctl disable --now cups cups-browsed`) oppure imposta un'altra `CUPS_PORT`
  (es. `6631`): l'annuncio Bonjour comunica la porta giusta ai client.
- **Stato della coda e dei lavori di stampa:**
  ```bash
  docker compose exec scanbridge lpstat -t
  ```
  L'interfaccia web di CUPS (`http://<server>:631/`) è consultabile da tutta la LAN; le
  pagine di amministrazione solo dal server.
- **Lo scanner sparisce dopo che la stampante è stata spenta.** Ricompare entro
  `RESCAN_INTERVAL` secondi da quando torna raggiungibile. Altrimenti:
  `docker compose restart`.

## Limiti

- Il tasto **"Scansione → PC"** sul pannello della stampante non funziona: usa un
  protocollo proprietario Samsung. La scansione si avvia dal computer.
- ADF, risoluzioni e opzioni disponibili dipendono dal backend (controlla con
  `docker compose exec scanbridge scanimage -A`).

## Crediti

- [AirSane](https://github.com/SimulPiscator/AirSane) di SimulPiscator (GPL-3.0), compilato
  dai sorgenti a un commit fissato (`AIRSANE_REF` nel `Dockerfile`), con le patch in
  `patches/`:
  - `airsane-doc-source-alias.patch`: il driver Samsung chiama l'opzione della sorgente
    `doc-source` invece del nome standard `source`. Senza patch AirSane mostrerebbe solo
    il piano di vetro, non l'ADF.
  - `airsane-name-override.patch`: opzioni `name`, `make-and-model` e `uuid` in
    `options.conf`, per annunciare lo scanner con il nome e l'UUID della stampante.
- [CUPS](https://openprinting.github.io/cups/) e cups-filters (OpenPrinting)
- [SANE](http://www.sane-project.org/), backend `xerox_mfp`
- Samsung Unified Linux Driver (proprietario, © Samsung/HP), pacchetti Debian da
  [SULDR](https://www.bchemnet.com/suldr/). L'immagine Docker lo scarica durante il build,
  e questo repository non lo ridistribuisce.
