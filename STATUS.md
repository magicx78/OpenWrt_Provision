# STATUS.md — OpenWrt Provisioning System

## Stand: v2.0 / Iteration 2

---

## ✅ FERTIG (Iteration 1 + 2)

### provision (ash-Skript)

- [x] Argument-Parser: –node-id, –profile, –apply, –dry-run, –validate-only, –rollback, –enable-11r/k/v, –verbose
- [x] Exit-Codes: 0 / 10 / 20 / 30 / 40
- [x] Config-Block am Anfang (alle Defaults inkl. MESH_PROTO)
- [x] Logging-System: MAIN_LOG + STEP_LOG, Levels INFO/OK/WARN/ERROR/FAIL/STEP
- [x] master.json Parser (jsonfilter-basiert): globale Felder, Node-spezifische Felder
- [x] Pre-Validation: wpad, regdomain, channel, ubus status, DSA bridge, Node-ID
- [x] **[v2] batman-adv Paket-Check**: nur wenn MESH_PROTO=batadv, klare Fehlermeldung
- [x] Backup: Timestamped Dir + metadata.json + SHA256
- [x] **[v2] Bugfix PIPESTATUS**: uci_batch_commit() entfernt, apply_config() nutzt Subshell + rc=$?
- [x] **[v2] Bugfix uci rename**: Alle rename @[-1] ersetzt durch `set wireless.NAME=wifi-iface`
- [x] **[v2] r0kh/r1kh Rendering**: render_r0kh_r1kh() liest master.json Arrays per jsonfilter-Loop
- [x] **[v2] DSA bridge-vlan**: render_network_lan() setzt `device='br-lan.<VLAN>'`; render_guest_isolated() erstellt `network.br_guest=device`
- [x] **[v2] mgmt-Interface**: render_mgmt_interface() rendert `network.mgmt` mit Node-IP auf `br-lan.<VLAN_MGMT>`
- [x] **[v2] render_network_mesh() fix**: proto='none' als Default (kein batadv), batadv opt-in per MESH_PROTO
- [x] Profil ap_roaming: 5G+2G AP, WPA3/SAE, 802.11r/k/v
- [x] Profil mesh_11s_backhaul: 5G Mesh, 2G AP
- [x] Profil client_backhaul: 5G STA, 2G AP, wwan-Interface
- [x] Profil guest_isolated: 5G+2G AP isolate, br-guest, Firewall-Zone, DHCP
- [x] Apply: uci batch + selective reload
- [x] Healthcheck: wireless status, bridge up, logread Fatal-Check, Firewall-Zonen
- [x] Auto-Rollback bei Apply-Fail und Healthcheck-Fail
- [x] Manueller –rollback Modus
- [x] UCI-Diff bei Fehler (in Logfile)
- [x] Cleanup-Trap (tmp files)

### master.json

- [x] **[v2] Bugfix**: nodes-Array korrekt mit `]` geschlossen (war `}`)
- [x] **[v2] r0kh/r1kh**: Vollständige Beispieleinträge für AP-Nodes (01, 02, 03, 10)
- [x] master_ap_bssid für alle Nodes gesetzt
- [x] Alle Felder: radios, ssids, passphrases, vlans, ip_plan, roaming, nodes

### Dokumentation

- [x] **[v2] README.md**: Setup, Dependencies, Master-Datei, CLI, Profile, Exit-Codes, Rollback, Logging, Troubleshooting
- [x] **[v2] ERROR_MATRIX.md**: Tabelle Fehler → Erkennung → Meldung → Rollback-Verhalten + Szenarien
- [x] **[v2] EXAMPLES.md**: Alle Profile, alle Flags, Schleife über alle Nodes, erwartete Ausgabe

---

## ⚠️ BEKANNTE LÜCKEN / TODO NÄCHSTE ITERATION

### Kritisch (Funktionalität)

- [ ] **jsonfilter Array-Queries `$.nodes[?(@.id=="03")]`**: Syntax-Kompatibilität je nach
  jsonfilter-Version. Bei Problemen: jshn-Loop als Fallback implementieren
- [ ] **DSA bridge-vlan port config**: Welche physischen Ports in welchem VLAN?
  Aktuell nur `.VLAN`-Sub-Devices ohne explizite Port-Konfiguration.
  Für produktiv: `bridge-vlan` Sections mit `ports 'lanX:t'` pro VLAN
- [ ] **validate-only Report**: Strukturierter Output (tabellarisch), kein reines log

### Wichtig (Vollständigkeit)

- [ ] **Rollback: spezifisches Backup wählen**: `--rollback-from <timestamp>`
- [ ] **logread Zeitfenster-Filter**: `logread -e "hostapd" -t` wenn `-t` verfügbar (OpenWrt 23.x)
- [ ] **wpad conflict: auto-remove**: Aktiv `wpad-basic` entfernen statt nur warnen
- [ ] **Dry-run Diff verbessern**: `uci show` vor Render vs. geplanter Batch (side-by-side)

### Nice-to-Have

- [ ] **`--list-nodes`**: zeigt alle Nodes mit ID, Hostname, Rolle aus master.json
- [ ] **`--status`**: `provision --status --node-id 03` → aktueller UCI-State
- [ ] **Multi-Node-Apply**: `--node-id all` oder `--node-id 01,02,03`
- [ ] **802.11r NAS-ID**: automatisch aus MAC ableiten statt hostname
- [ ] **RADIUS/WPA3-Enterprise**: optionales Profil

---

## 🐛 BEKANNTE BUGS (offen)

1. **jsonfilter Array-Filter**: `$.nodes[?(@.id=="03")]` — auf manchen OpenWrt-Versionen
   mit älterer jsonfilter-Version fehlerhaft. Testweise mit `jsonfilter --version` prüfen.
   Workaround: jshn-Loop über alle Nodes mit Vergleich in Shell.

2. **`set network.lan.device='br-lan.20'`**: Überschreibt evtl. bestehende LAN-Bridge-Konfiguration
   auf Systemen die noch kein VLAN auf br-lan haben. Vor Apply prüfen ob br-lan.20 tatsächlich
   vorhanden (ip link show br-lan.20).

---

## 📁 DATEIEN

| Datei | Status | Beschreibung |
|-------|--------|--------------|
| `provision` | ✅ v2.0 | Hauptskript (ash) |
| `master.json` | ✅ v2.0 | Beispiel-Config 10 Nodes inkl. r0kh/r1kh |
| `README.md` | ✅ v2.0 | Developer-Doku |
| `ERROR_MATRIX.md` | ✅ v2.0 | Fehlerfall-Tabelle |
| `EXAMPLES.md` | ✅ v2.0 | Alle Beispielaufrufe |
| `STATUS.md` | ✅ v2.0 | Diese Datei |

---

## 🔁 FORTSETZUNGS-PROMPT FÜR NÄCHSTE ITERATION

```
Du bist OpenWrt-Engineer. Wir arbeiten an einem ash-Provisioning-Skript für 10 OpenWrt-Router.

Stand: STATUS.md (angehängt). Skript `provision` v2.0, `master.json` v2.0 und Doku vorhanden.

Iteration 3 – bitte folgende Punkte umsetzen:

KRITISCH (must-have):
1. jshn-Fallback für Node-ID Lookup: falls jsonfilter '$.nodes[?(@.id=="XX")]' leer
   → jshn-Loop über $.nodes[*] mit manuellen String-Vergleich in ash
2. DSA bridge-vlan Port-Konfiguration: für VLAN_LAN und VLAN_MGMT explizite
   bridge-vlan sections rendern (ports 'lanX:t lanY:t cpu:t*') – Ports konfigurierbar
   per master.json nodes[].lan_ports Liste
3. validate-only Report: tabellarischer Output (printf), nicht nur log-Zeilen

WICHTIG:
4. --rollback-from <timestamp>: spezifisches Backup wählen
5. --list-nodes: alle Nodes aus master.json anzeigen
6. logread Zeitfenster: nach APPLY_TIME filtern (nur Fehler seit Apply)

Constraints: nur ash, nur OpenWrt-native Tools, DSA, Idempotenz, Exit-Codes beibehalten
```
