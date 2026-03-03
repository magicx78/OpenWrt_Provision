# provision v3.0 — OpenWrt Router Provisioning System

## Überblick

`provision` ist ein idempotentes ash-Shell-Skript für OpenWrt 22.03+ das folgende
Aufgaben automatisiert:

- **WPA3/SAE** (wpad-openssl) mit optionalem **802.11r/k/v** Roaming
- **DSA** VLAN-basiertes Netzwerk-Setup (Management / LAN / Guest)
- **802.11s Mesh Backhaul** (native; batadv optional)
- Vollständiges **Backup → Apply → Healthcheck → Auto-Rollback** mit Hard Gates

---

## Voraussetzungen

| Komponente | Mindestversion |
|------------|---------------|
| OpenWrt    | 22.03+        |
| `wpad-openssl` oder `wpad-full` | installiert, kein `wpad-basic` |
| `jsonfilter` | OpenWrt-Standard |
| `ubus`, `uci`, `ip`, `iw`, `logread` | OpenWrt-Standard |

```sh
# Paket-Setup (auf dem Router):
opkg update
opkg remove wpad-basic-wolfssl wpad-basic wpad-mini
opkg install wpad-openssl
```

---

## Installation

```sh
# master.json in Provisioning-Verzeichnis kopieren
mkdir -p /etc/provision/backups /etc/provision/logs
cp master.json /etc/provision/master.json

# Skript installieren
cp provision_v3 /usr/sbin/provision
chmod +x /usr/sbin/provision
```

---

## master.json

Zentrale Konfigurationsdatei mit:

| Bereich | Inhalt |
|---------|--------|
| `regdomain` / `country` | Länderkürzel (DE, AT, CH…) |
| `radios.radio5g/radio2g` | Kanal, HTMode, Txpower, disabled |
| `ssids` / `passphrases` | SSID-Namen und Passwörter |
| `encryption_policy` | `sae` (WPA3) oder `sae-mixed` (WPA2/3) |
| `roaming` | mobility_domain, r0kh[], r1kh[] für 802.11r |
| `vlans` | VLAN-IDs für mgmt/lan/guest |
| `ip_plan` | Subnetze (CIDR), DNS |
| `nodes[]` | Pro Node: id, hostname, mgmt_ip, role, master_ap_bssid |

**Wichtig bei 802.11r:** `roaming.r0kh` und `roaming.r1kh` müssen alle AP-Nodes
enthalten. Der `nas_id`-Wert in `r0kh` muss dem Hostname des jeweiligen Nodes entsprechen.

---

## CLI-Referenz

```
provision --node-id <id> --profile <profil> [optionen]
```

### Modi (genau einer erforderlich):

| Flag | Beschreibung |
|------|-------------|
| `--apply` | Backup + Render + Apply + Healthcheck |
| `--dry-run` | Render + UCI-Batch ausgeben, kein Commit |
| `--validate-only` | Nur Validierung, kein Apply |
| `--rollback` | Letztes gültiges Backup wiederherstellen |
| `--selftest` | Voraussetzungen prüfen, keine Änderungen |

### Optionen:

| Flag | Beschreibung |
|------|-------------|
| `--node-id <id>` | Node-ID aus master.json (z.B. `01`) |
| `--profile <name>` | Profil (siehe unten) |
| `--enable-11r` | 802.11r Fast BSS Transition (ap_roaming) |
| `--enable-11k` | 802.11k Radio Resource Management |
| `--enable-11v` | 802.11v BSS Transition Management |
| `--allow-dfs` | DFS-Kanäle explizit erlauben (sonst Exit 10) |
| `--rollback-from <ts>` | Spezifisches Backup (YYYYMMDD_HHMMSS) |
| `--verbose` | Erweiterte Ausgabe |

### Beispiele:

```sh
# Voraussetzungen prüfen
provision --selftest

# Validierung ohne Änderungen
provision --node-id 03 --profile ap_roaming --validate-only

# Dry-Run: UCI-Batch anzeigen
provision --node-id 03 --profile ap_roaming --apply --enable-11r --dry-run

# Produktiv Apply mit 802.11r/k/v
provision --node-id 03 --profile ap_roaming --apply --enable-11r --enable-11k --enable-11v

# Mesh Backhaul Node
provision --node-id 05 --profile mesh_11s_backhaul --apply

# Guest WLAN
provision --node-id 08 --profile guest_isolated --apply

# DFS explizit erlauben (Channel 100)
provision --node-id 01 --profile ap_roaming --apply --allow-dfs

# Rollback auf letztes gültiges Backup
provision --node-id 03 --rollback

# Rollback auf spezifisches Backup
provision --node-id 03 --rollback-from 20240315_143022

# Alle Nodes provisionieren (Shell-Schleife)
for id in 01 02 03 10; do
    provision --node-id "${id}" --profile ap_roaming --apply --enable-11r
done
```

---

## Profile

| Profil | Beschreibung | WLAN |
|--------|-------------|------|
| `ap_roaming` | Standard-AP mit WPA3/SAE, opt. 802.11r/k/v | 5G+2G AP |
| `mesh_11s_backhaul` | 802.11s Mesh-Node | 5G Mesh + 2G AP |
| `client_backhaul` | Repeater: verbindet sich per STA zum Master-AP | 5G STA + 2G AP |
| `guest_isolated` | Isoliertes Gast-WLAN, eigene Bridge+FW-Zone | 5G+2G AP isoliert |

---

## Exit-Codes

| Code | Bedeutung | Auto-Rollback |
|------|-----------|---------------|
| `0` | Erfolg | — |
| `10` | Validierungsfehler | Nein (kein Apply erfolgt) |
| `20` | Apply fehlgeschlagen | Ja |
| `30` | Healthcheck fehlgeschlagen | Ja |
| `40` | Rollback fehlgeschlagen | **Manuell!** |

Bei Exit 40: SSH-Zugang über Management-IP prüfen, ggf. Reset-Taste.

---

## Ablauf (--apply)

```
parse_args
    │
load_master_json + detect_radios
    │
run_validations ─── FAIL ──► Exit 10 (kein Apply)
    │ OK
create_backup ────── FAIL ──► Exit 20 (Hard Gate: kein Rollback nötig)
    │ OK (network+wireless gesichert + SHA256)
render_profile
    │
apply_config ─────── FAIL ──► Auto-Rollback ──► Exit 20 (oder 40)
    │ OK
run_healthcheck ──── FAIL ──► Auto-Rollback ──► Exit 30 (oder 40)
    │ OK (WLAN+Bridges+logread+FW)
Exit 0
```

**Hard Gates:**
1. Backup fehlgeschlagen → **kein Apply**
2. Validierung fehlgeschlagen → **kein Apply**
3. Healthcheck fehlgeschlagen → **Auto-Rollback**
4. Post-Rollback-WLAN tot → **Exit 40** (kein Exit 0)

---

## Rollback-Mechanismus

Backups liegen in `/etc/provision/backups/YYYYMMDD_HHMMSS_nodeXX_profil/`:

```
network           ← /etc/config/network
wireless          ← /etc/config/wireless
firewall          ← /etc/config/firewall
dhcp              ← /etc/config/dhcp
metadata.json     ← Timestamp, Node-ID, Profil, Version
checksums.sha256  ← SHA256 aller Dateien
```

`find_latest_valid_backup()` wählt das **neueste Backup mit:**
- `metadata.json` vorhanden
- `network` + `wireless` vorhanden
- SHA256-Checksums korrekt (wenn vorhanden)

---

## Idempotenz

Alle vom Skript erzeugten UCI-Sections sind markiert mit:
```
option provision_managed '1'
```

Beim nächsten Run werden alte managed-Sections **gelöscht** bevor neue geschrieben
werden. Re-Run erzeugt keine Duplikate.

---

## Logfiles

| Datei | Inhalt |
|-------|--------|
| `/var/log/provision.log` | Kumulatives Log aller Runs |
| `/etc/provision/logs/YYYYMMDD_HHMMSS.log` | Log pro Run inkl. UCI-Diff bei Fehler |

Log-Level: `START`, `STEP`, `INFO`, `OK`, `WARN`, `FAIL`, `ERROR`

---

## Failure Modes und Troubleshooting

### Exit 10: wpad-basic Konflikt
```
[FAIL] wpad-basic/mini ist GLEICHZEITIG mit wpad-openssl/full installiert
Fix: opkg remove wpad-basic-wolfssl wpad-basic wpad-mini
```

### Exit 10: DFS-Kanal
```
[FAIL] 5G-Channel 100 ist DFS-pflichtig
Fix: Channel 36/40/44/48 in master.json  ODER  --allow-dfs verwenden
```

### Exit 10: 802.11r ohne r0kh/r1kh
```
[FAIL] 802.11r aktiv aber roaming.r0kh leer!
Fix: r0kh/r1kh Einträge für alle AP-Nodes in master.json eintragen
```

### Exit 30: hostapd Fatal im Log
```
[FAIL] Kritische Fehler im Log seit Apply:
  >> hostapd: FAILED to set beacon parameters
Auto-Rollback wird ausgeführt...
```
Nach Rollback: Log analysieren, Konfiguration in master.json korrigieren.

### Exit 40: Rollback fehlgeschlagen
**Kritischer Zustand.** Sofortige Maßnahmen:
1. Konsolen-Zugang (seriell/UART) verwenden
2. `uci revert` versuchen
3. Im Notfall: Reset-Taste (30-30-30 Reset) oder Factory-Reset per sysupgrade

---

## Sicherheitshinweise

- `master.json` enthält Passwörter im Klartext → Dateiberechtigungen setzen: `chmod 600 /etc/provision/master.json`
- Der Token im Bootstrap-Script (`provisioning.sh`) sollte rotiert werden
- Für produktive Deployments: r0kh/r1kh Keys individuell pro Deployment wählen, nicht Default-Werte aus master.json
