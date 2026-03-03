# provision — OpenWrt Router Provisioning System

Version: 2.0.0 | Plattform: OpenWrt 22.03+ | Shell: ash | Netzwerk: DSA

## Arbeitsannahmen (bindend)

| Parameter | Wert | Änderbar |
|-----------|------|----------|
| Netzwerk-Stack | DSA (kein swconfig) | Nein |
| WLAN-Verschlüsselung | WPA3/SAE (oder sae-mixed) | per `encryption_policy` in master.json |
| wpad-Paket | wpad-openssl oder wpad-full | Validator prüft das |
| Mesh-Protokoll | `none` (reines 802.11s) oder `batadv` | `MESH_PROTO` im Config-Block |
| Hardware | identisch (gleicher Chipsatz, OpenWrt-Version) | — |
| Radio-Zuordnung | radio0 = 5 GHz, radio1 = 2.4 GHz | `render_radios()` im Skript |

---

## Setup

```sh
# 1. Provision-Verzeichnis anlegen
mkdir -p /etc/provision/backups /etc/provision/logs

# 2. Dateien kopieren
scp provision root@<router-ip>:/usr/local/bin/provision
scp master.json root@<router-ip>:/etc/provision/master.json

# 3. Executable setzen
chmod +x /usr/local/bin/provision

# 4. Abhängigkeiten prüfen (einmalig pro Router)
opkg update
opkg remove wpad-basic-wolfssl wpad-basic wpad-mini
opkg install wpad-openssl
# Für Mesh mit batman-adv (optional):
# opkg install kmod-batman-adv batctl-full
```

## Dependencies

| Paket/Tool | Zweck | Pflicht |
|------------|-------|---------|
| `wpad-openssl` oder `wpad-full` | WPA3/SAE + 802.11r | Ja |
| `jsonfilter` | JSON-Parsing | Ja (standard in OpenWrt) |
| `uci`, `ubus` | Konfiguration | Ja (immer vorhanden) |
| `iw` | Radio/Regdomain-Check | Ja |
| `bridge` / `ip` | Interface-Check | Ja |
| `sha256sum` | Backup-Checksums | Empfohlen |
| `kmod-batman-adv` | Mesh batadv-Modus | Nur wenn `MESH_PROTO=batadv` |

---

## Master-Datei (`/etc/provision/master.json`)

Single Source of Truth für alle Nodes. Felder:

| Feld | Beschreibung |
|------|--------------|
| `regdomain` | ISO-Ländercode (z.B. `DE`) |
| `radios.radio5g/radio2g` | Kanal, HTMode, TXPower, disabled |
| `ssids.main/guest/mesh` | SSID-Namen |
| `passphrases.main/guest/mesh` | WPA-Passphrasen |
| `encryption_policy` | `sae` (WPA3-only) oder `sae-mixed` |
| `roaming.mobility_domain` | 4 Hex-Zeichen, gleich für alle APs |
| `roaming.r0kh[]` | Liste der R0-Key-Holder `{nas_id, ip, key}` |
| `roaming.r1kh[]` | Liste der R1-Key-Holder `{r1kh_id, addr, key}` |
| `vlans.mgmt/lan/guest` | VLAN-IDs |
| `ip_plan.*` | Subnetze, DNS |
| `nodes[]` | Pro Node: id, hostname, mgmt_ip, role, master_ap_bssid |

---

## CLI

```
provision --node-id <id> --profile <profil> [optionen]

Optionen:
  --node-id <id>       Node-ID aus master.json (z.B. 03)
  --profile <name>     Profil (siehe unten)
  --apply              Konfiguration anwenden + Health-Check
  --dry-run            UCI-Batch ausgeben, nichts schreiben
  --validate-only      Nur Vorab-Validierung
  --rollback           Letztes Backup für diese Node wiederherstellen
  --enable-11r         802.11r Fast BSS Transition (nur ap_roaming)
  --enable-11k         802.11k Radio Resource Management (nur ap_roaming)
  --enable-11v         802.11v BSS Transition Management (nur ap_roaming)
  --verbose            Debug-Ausgabe auf stdout
```

---

## Profile

### `ap_roaming`
- 5G + 2G Access Point mit WPA3/SAE
- Optional: `--enable-11r` (FT), `--enable-11k` (RRM), `--enable-11v` (BTM)
- Bei `--enable-11r`: r0kh/r1kh aus master.json werden gesetzt
- Netzwerk: LAN auf `br-lan.<VLAN_LAN>`, mgmt auf `br-lan.<VLAN_MGMT>`

### `mesh_11s_backhaul`
- 5G 802.11s Mesh-Backhaul (SAE-Authentifizierung)
- 2G zusätzlicher lokaler AP (SSID main)
- `MESH_PROTO=none` (default): reines 802.11s-Bridging, kein batman-adv
- `MESH_PROTO=batadv`: batman-adv (kmod-batman-adv erforderlich)

### `client_backhaul`
- 5G STA: verbindet sich zu Master-AP (BSSID optional aus master.json)
- 2G lokaler AP für Clients
- WAN-Interface `wwan` per DHCP vom Master-AP
- Benötigt: `master_ap_ip` in master.json für die Node

### `guest_isolated`
- 5G + 2G Gast-AP mit Client-Isolation (`isolate=1`)
- Eigene Bridge `br-guest`, VLAN-ID aus master.json
- Eigene Firewall-Zone: input=REJECT, forward=REJECT, output=ACCEPT
- Forwarding: guest → wan (kein guest → lan)
- DHCP-Pool: .100 – .249, Leasetime 1h

---

## Exit-Codes

| Code | Bedeutung |
|------|-----------|
| 0 | OK — alles erfolgreich |
| 10 | Validation failed — Abbruch vor Apply |
| 20 | Apply failed — Auto-Rollback ausgelöst |
| 30 | Healthcheck failed — Auto-Rollback ausgelöst |
| 40 | Rollback failed — manueller Eingriff nötig |

---

## Rollback

**Automatisch:** Bei Exit-Code 20 oder 30 wird automatisch das zuletzt erstellte Backup eingespielt.

**Manuell:**
```sh
provision --node-id 03 --rollback
```

Backups liegen in: `/etc/provision/backups/<timestamp>_node<id>_<profil>/`

Inhalt pro Backup:
- `network`, `wireless`, `firewall`, `dhcp` — Kopien von `/etc/config/`
- `metadata.json` — node-id, profile, Flags, Timestamp
- `checksums.sha256` — SHA256-Hashes der gesicherten Dateien

---

## Logging

**Hauptlog:** `/var/log/provision.log` (persistent bis Neustart)
**Step-Log:** `/etc/provision/logs/<timestamp>.log` (persistent)

Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] node=XX profile=YYY <message>`

Levels: `STEP` → `INFO` → `OK` → `WARN` → `ERROR` → `FAIL`

Bei Fehler im Log:
- UCI-State (`uci show wireless/network/firewall/dhcp`) als Snapshot
- Relevante `logread`-Zeilen (hostapd/netifd, letzte 200 Zeilen)

---

## Idempotenz

Alle vom Tool gesetzten UCI-Sections haben `option provision_managed '1'`.
Vor jedem Apply werden diese Sections gelöscht und neu gesetzt.
Mehrfaches Ausführen ist sicher.

---

## Troubleshooting

| Problem | Prüfung | Lösung |
|---------|---------|--------|
| `wpad-basic` Konflikt | `opkg list-installed \| grep wpad` | `opkg remove wpad-basic-wolfssl && opkg install wpad-openssl` |
| Radio antwortet nicht | `ubus call network.wireless status` | `wifi down && wifi up` |
| Regdomain falsch | `iw reg get` | `iw reg set DE` oder UCI `option country 'DE'` |
| Backup-Verzeichnis fehlt | `ls /etc/provision/backups/` | `mkdir -p /etc/provision/backups` |
| jsonfilter fehlt | `which jsonfilter` | `opkg install jsonfilter` |
| DFS-Channel gesperrt | `iw list` → DFS-Channels | Channel auf 36/40/44/48 setzen |
| batman-adv fehlt | `opkg list-installed \| grep batman` | `opkg install kmod-batman-adv batctl-full` oder `MESH_PROTO=none` |
