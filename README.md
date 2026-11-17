# samsung-m2070fw-bridge-docker

Rende lo **scanner** della Samsung Xpress **M2070FW** disponibile in rete come scanner
**AirScan/eSCL**, utilizzabile senza driver da macOS (Acquisizione Immagine, Anteprima),
Windows 10/11 e Linux (`sane-airscan`).

Serve perché i driver Samsung per macOS sono solo Intel e smettono di funzionare
senza Rosetta 2.

## Come funziona

```
 Mac / PC ──eSCL (HTTP :8090) + Bonjour──▶ [ container ]  ──SANE xerox_mfp (TCP :9400)──▶ M2070FW
                                         AirSane + avahi
```

- **SANE**, con il backend open source `xerox_mfp` (che supporta la M2070), parla con la
  stampante in rete sulla porta 9400.
- **[AirSane](https://github.com/SimulPiscator/AirSane)** prende lo scanner SANE e lo
  pubblica come scanner eSCL, annunciato via mDNS/Bonjour.
- Un piccolo watcher controlla ogni minuto se la stampante è raggiungibile. Quando torna
  online (era spenta, si è riavviata) fa ripetere la ricerca ad AirSane, senza riavviare
  il container.

**La stampa non passa da qui.** La M2070FW supporta AirPrint nel firmware, quindi macOS
continua a stamparci direttamente, anche senza il driver Samsung.

## Requisiti

- Un host Linux sulla **stessa LAN/subnet** della stampante e dei client (x86_64 o ARM64)
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
[bridge] Found: device `xerox_mfp:tcp 192.168.1.50' is a Samsung M2070 Series multi-function peripheral
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
   docker compose exec -T scanbridge scanimage --jpeg=no --format=png > test.png
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
| `SANE_JPEG`        | `no`    | Compressione JPEG del backend: lasciala a `no` (vedi sotto) |
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
  Per i dettagli metti `DEBUG=true`, oppure:
  ```bash
  docker compose exec -e SANE_DEBUG_XEROX_MFP=4 scanbridge scanimage -L
  ```
- **Scansioni a colori che falliscono con `Not a JPEG file: starts with 0x00 0x00`**, o
  scanner bloccato/lentissimo dopo una scansione a colori. Con la compressione JPEG attiva
  (default del backend) i dati a colori della M2070FW arrivano corrotti e lo scanner resta
  in uno stato bloccato. Il container imposta `jpeg no` per questo. Se usi un
  `options.conf` tuo, ricordati di includere `jpeg no`. Per sbloccare lo scanner: spegni e
  riaccendi la stampante, poi `docker compose restart`. Per i test a mano con `scanimage`
  aggiungi sempre `--jpeg=no`.
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
- ADF e risoluzioni disponibili dipendono dal backend `xerox_mfp` (controlla con
  `scanimage -A`).

## Crediti

- [AirSane](https://github.com/SimulPiscator/AirSane) di SimulPiscator (GPL-3.0), compilato
  dai sorgenti a un commit fissato (`AIRSANE_REF` nel `Dockerfile`)
- [SANE](http://www.sane-project.org/), backend `xerox_mfp`
