# ERROR_MATRIX — Fehlerfall-Tabelle

## Validator-Fehler (Exit 10)

| Fehler | Erkennung | Meldung | Rollback |
|--------|-----------|---------|----------|
| `wpad-basic` statt `wpad-openssl` installiert | `opkg list-installed \| grep -E '^wpad-openssl\|^wpad-full'` → kein Treffer | `Kein geeignetes wpad-Paket. opkg install wpad-openssl` | Kein Apply → kein Rollback nötig |
| `kmod-batman-adv` fehlt bei `MESH_PROTO=batadv` | `opkg list-installed \| grep ^kmod-batman-adv` → kein Treffer | `MESH_PROTO=batadv aber kmod-batman-adv fehlt` | Kein Apply |
| Node-ID nicht in master.json | `jsonfilter $.nodes[?(@.id=="XX")].id` → leer | `Node-ID 'XX' nicht in master.json` | Kein Apply |
| `mgmt_ip` leer für Node | `CFG_NODE_MGMT_IP` leer nach JSON-Parse | `mgmt_ip nicht gesetzt für Node XX` | Kein Apply |
| VLAN-IDs doppelt | Vergleich mgmt/lan/guest IDs | `VLAN-ID XX doppelt vergeben` | Kein Apply |
| Subnetz-Kollision | 3-Oktet-Vergleich mgmt/lan/guest | `Subnetz-Kollision! mgmt=... lan=... guest=...` | Kein Apply |
| `master_ap_ip` fehlt bei `client_backhaul` | `CFG_NODE_MASTER_AP` leer | `client_backhaul benötigt master_ap_ip` | Kein Apply |
| Ungültiges Profil | case-Match in `parse_args` | `Unbekanntes Profil: XYZ` | Kein Apply |

## Apply-Fehler (Exit 20)

| Fehler | Erkennung | Meldung | Rollback |
|--------|-----------|---------|----------|
| `uci batch` Fehler (Syntax) | `uci_rc != 0` nach Subshell-Exec | `uci batch fehlgeschlagen (rc=X): <output>` | Auto-Rollback + Reload |
| `uci commit` schlägt fehl | Einzelner commit-Aufruf returniert != 0 | `commit <cfg>: Fehler` (warn, kein hard fail) | Nur bei uci batch Fehler |
| Backup-Verzeichnis nicht erstellbar | `mkdir -p` returniert != 0 | `Backup-Verzeichnis konnte nicht erstellt werden` | Apply wird abgebrochen (kein Backup = kein Apply) |
| Backup-Datei nicht kopierbar | `cp` returniert != 0 | `Backup fehlgeschlagen für: <cfg>` (warn) | Apply läuft weiter, Rollback-Risiko erhöht |

## Healthcheck-Fehler (Exit 30)

| Fehler | Erkennung | Meldung | Rollback |
|--------|-----------|---------|----------|
| AP-Mode Interface fehlt | `ubus call network.wireless status` kein `"mode":"ap"` nach 6×5s | `WLAN-Interface nach 30s nicht gefunden` | Auto-Rollback |
| Mesh-Interface fehlt | `ubus status` kein `"mode":"mesh"` | wie oben | Auto-Rollback |
| STA-Interface fehlt | `ubus status` kein `"mode":"sta"` | wie oben | Auto-Rollback |
| Guest-SSID fehlt | `ubus status` kein `CFG_SSID_GUEST` | wie oben | Auto-Rollback |
| `br-lan` fehlt | `ip link show type bridge \| grep br-lan` → kein Treffer | `br-lan nicht gefunden` (warn) | Kein hard fail |
| `br-guest` fehlt (guest-Profil) | `ip link \| grep br-guest` → kein Treffer | `Guest-Bridge nicht gefunden` | Auto-Rollback |
| Firewall-Zone guest fehlt | `uci show firewall \| grep zone_guest` → kein Treffer | `Firewall-Zone 'guest' fehlt` | Auto-Rollback |
| hostapd Fatal-Error in logread | `logread \| grep -iE 'hostapd.*fatal\|error\|failed'` → Treffer | `Fatal-Errors im Log: <zeilen>` | Soft-fail (check_logread_errors ist warn-only) |

## Rollback-Fehler (Exit 40)

| Fehler | Erkennung | Meldung | Folge |
|--------|-----------|---------|-------|
| Kein Backup für Node | `ls ${BACKUP_BASE}/*_nodeXX_*` → leer | `Kein Backup gefunden für Node XX` | Exit 40, **manueller Eingriff nötig** |
| Backup-Datei nicht kopierbar | `cp` returniert != 0 beim Restore | `Konnte /etc/config/<cfg> nicht wiederherstellen` | Exit 40 |
| WLAN nach Rollback tot | `ubus call network.wireless status` → leer | `WLAN-Subsystem antwortet nicht` (warn) | Exit 0 (transient möglich) |

## Typische Fehler-Szenarien in der Praxis

### Szenario 1: WPA3 funktioniert nicht
```
FAIL Kein geeignetes wpad-Paket installiert!
```
**Ursache:** `wpad-basic-wolfssl` installiert (kein SAE/802.11r).
**Fix:** `opkg remove wpad-basic-wolfssl && opkg install wpad-openssl && reboot`

### Szenario 2: 802.11r — r0kh fehlt
```
WARN Keine r0kh-Einträge in master.json (roaming.r0kh)
```
**Ursache:** `roaming.r0kh` ist leer oder fehlt in master.json.
**Fix:** r0kh-Einträge für alle AP-Nodes in master.json eintragen.

### Szenario 3: Mesh-Interface startet nicht
```
FAIL Healthcheck: WLAN-Interface nach 30s nicht gefunden
```
**Ursache:** 802.11s erfordert `mesh_id` exakt gleich auf allen Nodes + gleichen Kanal.
**Fix:** Sicherstellen dass alle Mesh-Nodes denselben Channel und `mesh_id` haben.

### Szenario 4: Guest-Bridge fehlt nach Apply
```
FAIL Healthcheck: Guest-Bridge nicht gefunden
→ Auto-Rollback...
```
**Ursache:** DSA `set network.br_guest=device` wird auf älteren OpenWrt-Versionen (<21.02) nicht unterstützt.
**Fix:** OpenWrt 22.03+ verwenden (DSA device model erforderlich).

### Szenario 5: DFS-Channel blockiert
```
WARN 5G-Channel 100 ist DFS-pflichtig (Radar-Detection erforderlich)
```
**Ursache:** Channel im DFS-Bereich (52–144), Radar-Detection läuft.
**Fix:** Channel auf 36/40/44/48 setzen in master.json.

### Szenario 6: uci rename schlägt fehl (v1.0)
```
uci batch fehlgeschlagen (rc=1)
```
**Ursache:** `rename @[-1]` nach `add` in manchen OpenWrt-Versionen fehlerhaft.
**Fix:** Seit v2.0 wird `set wireless.wlan_NAME=wifi-iface` verwendet (kein rename mehr).
