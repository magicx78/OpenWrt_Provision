# EXAMPLES — Beispielaufrufe

## Profil: ap_roaming

```sh
# Validate only — prüft Pakete, Regdomain, Channel, VLAN-Konsistenz
provision --node-id 01 --profile ap_roaming --validate-only

# Dry-run — zeigt UCI-Batch ohne Schreiben
provision --node-id 01 --profile ap_roaming --dry-run

# Apply — WPA3/SAE only, kein Roaming
provision --node-id 01 --profile ap_roaming --apply

# Apply mit 802.11r (Fast BSS Transition)
# Setzt mobility_domain, ft_over_ds, r0kh, r1kh aus master.json
provision --node-id 01 --profile ap_roaming --apply --enable-11r

# Apply mit 802.11r + 802.11k (Radio Resource Measurement)
provision --node-id 02 --profile ap_roaming --apply --enable-11r --enable-11k

# Apply mit vollem Roaming-Stack: 11r + 11k + 11v
provision --node-id 03 --profile ap_roaming --apply --enable-11r --enable-11k --enable-11v

# Wie oben + verbose output auf stdout
provision --node-id 03 --profile ap_roaming --apply --enable-11r --enable-11k --enable-11v --verbose

# Dry-run mit 11r — zeigt r0kh/r1kh UCI list Einträge
provision --node-id 01 --profile ap_roaming --dry-run --enable-11r
```

## Profil: mesh_11s_backhaul

```sh
# Validate only
provision --node-id 04 --profile mesh_11s_backhaul --validate-only

# Dry-run (prüft ob batman-adv nötig wenn MESH_PROTO=batadv)
provision --node-id 04 --profile mesh_11s_backhaul --dry-run

# Apply — reines 802.11s (MESH_PROTO=none, Standard)
provision --node-id 04 --profile mesh_11s_backhaul --apply

# Apply — zweiter Mesh-Node
provision --node-id 05 --profile mesh_11s_backhaul --apply

# Apply mit batman-adv (MESH_PROTO muss im Skript-Config-Block auf 'batadv' stehen)
# Vorher: opkg install kmod-batman-adv batctl-full
# Im Skript Config-Block: MESH_PROTO="batadv"
provision --node-id 04 --profile mesh_11s_backhaul --apply --verbose
```

## Profil: client_backhaul

```sh
# Validate only — prüft ob master_ap_ip in master.json gesetzt ist
provision --node-id 06 --profile client_backhaul --validate-only

# Dry-run — zeigt STA-Config mit BSSID-Option
provision --node-id 06 --profile client_backhaul --dry-run

# Apply — Node 06 verbindet sich als STA zu Master-AP (BSSID aus master.json)
provision --node-id 06 --profile client_backhaul --apply

# Apply — Node 07 (anderer Master-AP)
provision --node-id 07 --profile client_backhaul --apply

# Mit verbose — zeigt wwan-Interface + local AP UCI
provision --node-id 06 --profile client_backhaul --apply --verbose
```

## Profil: guest_isolated

```sh
# Validate only
provision --node-id 08 --profile guest_isolated --validate-only

# Dry-run — zeigt br-guest device, guest interface, firewall zone, DHCP pool
provision --node-id 08 --profile guest_isolated --dry-run

# Apply
provision --node-id 08 --profile guest_isolated --apply

# Apply Node 09
provision --node-id 09 --profile guest_isolated --apply

# Mit verbose
provision --node-id 08 --profile guest_isolated --apply --verbose
```

## Rollback

```sh
# Manueller Rollback auf letztes Backup
provision --node-id 03 --rollback

# Rollback nach fehlgeschlagenem Apply (automatisch ausgelöst, aber auch manuell möglich)
provision --node-id 01 --rollback

# Verbose Rollback (mehr Log-Output)
provision --node-id 05 --rollback --verbose
```

## Alle Nodes provisionieren (Shell-Schleife)

```sh
# Alle ap_roaming Nodes (01, 02, 03, 10) mit vollem Roaming-Stack
for id in 01 02 03 10; do
    echo "=== Node $id ==="
    provision --node-id "$id" --profile ap_roaming --apply --enable-11r --enable-11k --enable-11v
done

# Alle Nodes laut ihrer Rolle in master.json (Beispiel)
# (setzt voraus: jq oder jsonfilter verfügbar auf Deploy-System)
for id in 01 02 03 04 05 06 07 08 09 10; do
    role=$(jsonfilter -i /etc/provision/master.json -e "$.nodes[?(@.id==\"${id}\")].role")
    provision --node-id "$id" --profile "$role" --apply
done
```

## Validate-only für alle Nodes

```sh
for id in 01 02 03 04 05 06 07 08 09 10; do
    echo -n "Node $id: "
    provision --node-id "$id" --profile ap_roaming --validate-only 2>&1 | tail -1
done
```

## Erwartete Ausgabe (Dry-run ap_roaming --enable-11r)

```
========================================
 provision v2.0.0
 Node: 01  Profil: ap_roaming
 Mon Mar  3 14:00:00 2026
========================================
==> Lade master.json: /etc/provision/master.json
==> Paket-Validierung (wpad)
==> Node-ID Validierung
==> Regdomain-Validierung
==> Channel/HTMode-Validierung via iw list
==> WLAN-Status via ubus
==> DSA/Bridge-Konsistenz-Check
==> Modus: DRY-RUN
==> Render: system
==> Render: wireless radios
==> Render: Profil ap_roaming
=== DRY-RUN: UCI Batch ===
set system.@system[0].hostname='router-01'
...
set wireless.wlan_ap5g=wifi-iface
set wireless.wlan_ap5g.device='radio0'
set wireless.wlan_ap5g.mode='ap'
set wireless.wlan_ap5g.ssid='HomeNetwork'
set wireless.wlan_ap5g.encryption='sae'
set wireless.wlan_ap5g.ieee80211r='1'
set wireless.wlan_ap5g.mobility_domain='ab12'
list wireless.wlan_ap5g.r0kh='router-01 10.0.10.1 r0kh_shared_key_changeme_2024'
list wireless.wlan_ap5g.r0kh='router-02 10.0.10.2 r0kh_shared_key_changeme_2024'
...
set network.mgmt=interface
set network.mgmt.device='br-lan.10'
set network.mgmt.ipaddr='10.0.10.1'
...
=== END UCI Batch ===
  Dry-Run abgeschlossen. Kein Commit.
```
