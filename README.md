# samsung-m2070fw-bridge-docker

Rende lo **scanner** della Samsung Xpress **M2070FW** disponibile in rete come scanner
**AirScan/eSCL**, utilizzabile senza driver da macOS (Acquisizione Immagine, Anteprima),
Windows 10/11 e Linux (`sane-airscan`).

Serve perché i driver Samsung per macOS sono solo Intel e smettono di funzionare
senza Rosetta 2.

## Come funziona

```
 Mac / PC ──eSCL (HTTP :8090) + Bonjour──▶ [ container ]  ──SANE smfp (driver Samsung)──▶ M2070FW
                                         AirSane + avahi
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

**La stampa non passa da qui.** La M2070FW supporta AirPrint nel firmware, quindi macOS
continua a stamparci direttamente, anche senza il driver Samsung.

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
2. **macOS:** apri **Acquisizione Immagine**. Lo scanner compare in "Condivisi" o
   "Dispositivi". In Impostazioni di Sistema → Stampanti e Scanner risulta come
   "Bonjour Scanner".
3. **Da riga di comando, nel container:**
   ```bash
   docker compose exec scanbridge scanimage -L
   docker compose exec scanbridge scanimage -A                     # opzioni del backend
   docker compose exec -T scanbridge scanimage --format=png > test.png
   ```

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
  e TCP 8090. Il Mac deve stare nella stessa subnet: mDNS non attraversa i router (e
  nemmeno, di solito, le VLAN separate o una Wi-Fi "ospiti").
- **Acquisizione Immagine dà "error 21345".** Problema noto di AirSane: abilita IPv6 sulla
  rete e sull'host, poi riavvia (vedi il README di AirSane).
- **Scansioni troppo scure o troppo chiare.** Regola `gray-gamma` / `color-gamma` in
  `options.conf`.
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
  dai sorgenti a un commit fissato (`AIRSANE_REF` nel `Dockerfile`)
- [SANE](http://www.sane-project.org/), backend `xerox_mfp`
- Samsung Unified Linux Driver (proprietario, © Samsung/HP), pacchetti Debian da
  [SULDR](https://www.bchemnet.com/suldr/). L'immagine Docker lo scarica durante il build,
  e questo repository non lo ridistribuisce.
