#!/bin/ash
# tests/run.sh — provision_v3 Test-Runner (BusyBox/ash, GNU-frei)
#
# Strategie: Stubs in tests/stubs/ haben via PATH-Vorrang Vorrang vor echten Tools.
# init.d-Stubs liegen in tests/stubs/init.d/ und werden per INIT_D_DIR gesetzt.
# Kein --apply in diesen Tests → init.d-Stubs nur als Safety-Net nötig.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVISION="${SCRIPT_DIR}/../provision_v3"
STUBS_DIR="${SCRIPT_DIR}/stubs"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------
_pass() { PASS=$((PASS+1)); printf '[PASS] %s\n' "$1"; }
_fail() { FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$1"; }

# assert_exit <label> <expected_rc> <cmd...>
assert_exit() {
    local label="$1" expected="$2"; shift 2
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [ "${actual}" -eq "${expected}" ]; then
        _pass "${label} (exit=${expected})"
    else
        _fail "${label} (exit=${actual}, erwartet=${expected})"
    fi
}

# assert_contains <label> <grep_pattern> <cmd...>
assert_contains() {
    local label="$1" pat="$2"; shift 2
    local out actual=0
    out="$("$@" 2>&1)" || actual=$?
    if printf '%s\n' "${out}" | grep -qiE "${pat}"; then
        _pass "${label}"
    else
        _fail "${label} — Pattern '${pat}' nicht in: ${out}"
    fi
}

# ---------------------------------------------------------------------------
# Stubs aufbauen
# setup_stubs [--no-opkg]  →  ohne --no-opkg wird opkg-Stub installiert
# ---------------------------------------------------------------------------
setup_stubs() {
    local install_opkg=1
    [ "$1" = "--no-opkg" ] && install_opkg=0

    mkdir -p "${STUBS_DIR}" "${STUBS_DIR}/init.d"

    # --- opkg ---
    if [ "${install_opkg}" -eq 1 ]; then
        cat > "${STUBS_DIR}/opkg" <<'EOF'
#!/bin/sh
[ "$1" = "list-installed" ] && {
    printf '%s\n' "${STUB_OPKG_OUTPUT:-wpad-openssl - 2024}"
    exit 0
}
exit 0
EOF
    else
        rm -f "${STUBS_DIR}/opkg"
    fi

    # --- uci ---
    cat > "${STUBS_DIR}/uci" <<'EOF'
#!/bin/sh
case "$*" in
    "show wireless"*)
        printf 'wireless.radio0=wifi-device\nwireless.radio0.band=5g\n'
        printf 'wireless.radio1=wifi-device\nwireless.radio1.band=2g\n'
        ;;
    "-q get wireless.radio0.band") printf '5g\n' ;;
    "-q get wireless.radio1.band") printf '2g\n' ;;
    "show network.lan"*)           printf 'network.lan=interface\n' ;;
    *)  true ;;
esac
exit 0
EOF

    # --- ubus ---
    cat > "${STUBS_DIR}/ubus" <<'EOF'
#!/bin/sh
case "$*" in
    "list"*) printf 'network\nnetwork.wireless\n' ;;
    "call network.wireless status"*)
        printf '{"radio0":{"up":true,"mode":"ap"},"radio1":{"up":true,"mode":"ap"}}\n' ;;
    *) true ;;
esac
exit 0
EOF

    # --- iw ---
    cat > "${STUBS_DIR}/iw" <<'EOF'
#!/bin/sh
case "$*" in
    "reg get"*) printf 'country DE: DFS-ETSI\n' ;;
    "list"*)    printf 'Band 1:\n  Frequencies:\n    * 5180 MHz [36]\n' ;;
    *)          true ;;
esac
exit 0
EOF

    # --- logread ---
    # STUB_LOGREAD_FILE kann auf eine Datei mit Zeileninhalt zeigen.
    # Default: 5 harmlose + 1 Fehlerzeile + 1 weitere Zeile
    cat > "${STUBS_DIR}/logread" <<'EOF'
#!/bin/sh
if [ -n "${STUB_LOGREAD_FILE}" ] && [ -f "${STUB_LOGREAD_FILE}" ]; then
    cat "${STUB_LOGREAD_FILE}"
else
    printf 'info1\ninfo2\ninfo3\ninfo4\ninfo5\nhostapd: FAILED to set beacon parameters\ninfo7\n'
fi
EOF

    # --- wifi ---
    cat > "${STUBS_DIR}/wifi" <<'EOF'
#!/bin/sh
exit 0
EOF

    # --- jsonfilter ---
    cat > "${STUBS_DIR}/jsonfilter" <<'EOF'
#!/bin/sh
# Gibt STUB_JF_VAL zurück; liest aus stdin wenn keine Datei gegeben
printf '%s\n' "${STUB_JF_VAL:-}"
exit 0
EOF

    # --- sha256sum ---
    cat > "${STUBS_DIR}/sha256sum" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    printf 'aabbccdd1234  %s\n' "$1"
    shift
done
exit 0
EOF

    # --- init.d Dummy-Skripte (Safety-Net, werden bei --validate-only nicht aufgerufen) ---
    for svc in network firewall dnsmasq; do
        cat > "${STUBS_DIR}/init.d/${svc}" <<'EOF'
#!/bin/sh
exit 0
EOF
    done

    chmod +x "${STUBS_DIR}"/* "${STUBS_DIR}/init.d"/*

    # PATH-Vorrang: Stubs vor Systemtools
    export PATH="${STUBS_DIR}:${PATH}"
}

# ---------------------------------------------------------------------------
# UNIT-Hilfsfunktion: subnets_overlap() aus provision_v3 laden
# ---------------------------------------------------------------------------
load_subnets_overlap() {
    # Extrahiert nur die Funktion (Closing-} muss in Spalte 0 stehen)
    eval "$(sed -n '/^subnets_overlap()/,/^}$/p' "${PROVISION}")"
}

# ===========================================================================
# T01  Positiv — gleiche /24 erkennt Überlappung
# ===========================================================================
test_T01_overlap_same_24() {
    load_subnets_overlap
    if subnets_overlap "192.168.1.0/24" "192.168.1.0/24"; then
        _pass "T01 subnets_overlap: gleiche /24 → rc=0 (overlap)"
    else
        _fail "T01 subnets_overlap: gleiche /24 → sollte rc=0 sein"
    fi
}

# ===========================================================================
# T02  Positiv — /20 enthält /24 (partial-bits Pfad)
# ===========================================================================
test_T02_overlap_20_contains_24() {
    load_subnets_overlap
    # 10.0.16.0/20 deckt 10.0.16.0–10.0.31.255 ab; 10.0.20.0/24 liegt darin
    if subnets_overlap "10.0.16.0/20" "10.0.20.0/24"; then
        _pass "T02 subnets_overlap: /20 enthält /24 → rc=0 (overlap)"
    else
        _fail "T02 subnets_overlap: /20 vs eingebettetes /24 → sollte überlappen"
    fi
}

# ===========================================================================
# T03  Negativ — verschiedene /24 überlappen sich NICHT
# ===========================================================================
test_T03_no_overlap_different_24() {
    load_subnets_overlap
    if subnets_overlap "192.168.1.0/24" "192.168.2.0/24"; then
        _fail "T03 subnets_overlap: .1/24 vs .2/24 → darf nicht überlappen (rc=0 unerwartet)"
    else
        _pass "T03 subnets_overlap: .1/24 vs .2/24 → korrekt rc=1 (kein overlap)"
    fi
}

# ===========================================================================
# T04  Edge — pfx1 leer (CIDR ohne /N): muss return 1 liefern (Bug-Fix-Verifikation)
# ===========================================================================
test_T04_empty_prefix_returns_1() {
    load_subnets_overlap
    # "192.168.1.0" hat kein '/' → pfx1 wird leer durch ${cidr##*/}
    if subnets_overlap "192.168.1.0" "192.168.1.0/24"; then
        _fail "T04 subnets_overlap: leeres pfx1 → rc=0 (Bug! if-Fix nicht aktiv?)"
    else
        _pass "T04 subnets_overlap: leeres pfx1 → korrekt rc=1 (if-Fix aktiv)"
    fi
}

# ===========================================================================
# T05  Negativ — /20 vs entferntes /24 (anderes /20-Segment)
# ===========================================================================
test_T05_no_overlap_20_vs_distant_24() {
    load_subnets_overlap
    # 10.0.16.0/20 deckt bis 10.0.31.255; 10.0.32.0/24 liegt AUSSERHALB
    if subnets_overlap "10.0.16.0/20" "10.0.32.0/24"; then
        _fail "T05 subnets_overlap: 10.0.16/20 vs 10.0.32/24 → darf nicht überlappen"
    else
        _pass "T05 subnets_overlap: 10.0.16/20 vs 10.0.32/24 → korrekt rc=1"
    fi
}

# ===========================================================================
# T06  Negativ — validate_packages: opkg fehlt → Exit 10 + Fehlermeldung
# ===========================================================================
test_T06_validate_no_opkg() {
    setup_stubs --no-opkg   # opkg absichtlich NICHT installieren

    local tmpdir; tmpdir="$(mktemp -d)"
    # Minimales master.json mit einem gültigen Node
    cat > "${tmpdir}/master.json" <<'JSON'
{
  "regdomain":"DE","country":"DE",
  "radios":{
    "radio5g":{"band":"5g","channel":"36","htmode":"VHT80","txpower":"20","disabled":"0"},
    "radio2g":{"band":"2g","channel":"6","htmode":"HT20","txpower":"20","disabled":"0"}
  },
  "ssids":{"main":"TestNet","guest":"TestGuest","mesh":"TestMesh"},
  "passphrases":{"main":"Pass1word!","guest":"Pass2word!","mesh":"Pass3word!"},
  "encryption_policy":"sae",
  "roaming":{"mobility_domain":"ab12","ft_over_ds":"1","r0kh":[],"r1kh":[]},
  "vlans":{"mgmt":"10","lan":"20","guest":"30"},
  "ip_plan":{
    "mgmt_subnet":"10.0.10.0/24","lan_subnet":"192.168.20.0/24",
    "guest_subnet":"192.168.30.0/24","dns_primary":"1.1.1.1","dns_secondary":"8.8.8.8"
  },
  "nodes":[{"id":"01","hostname":"r01","mgmt_ip":"10.0.10.1",
    "role":"ap_roaming","master_ap_ip":"","master_ap_bssid":""}]
}
JSON

    local out rc=0
    out="$(PROVISION_DIR="${tmpdir}" MASTER_JSON="${tmpdir}/master.json" \
        ash "${PROVISION}" --node-id 01 --profile ap_roaming --validate-only 2>&1)" \
        || rc=$?

    # Prüfe Fehlermeldung
    if printf '%s\n' "${out}" | grep -qiE "opkg.*nicht gefunden|opkg.*not found"; then
        _pass "T06 opkg fehlt → Fehlermeldung 'opkg nicht gefunden' ausgegeben"
    else
        _fail "T06 opkg fehlt → Fehlermeldung erwartet, bekommen: ${out}"
    fi

    # Prüfe Exit-Code 10 (EXIT_VALIDATION)
    if [ "${rc}" -eq 10 ]; then
        _pass "T06 opkg fehlt → Exit 10 (EXIT_VALIDATION korrekt)"
    else
        _fail "T06 opkg fehlt → Exit ${rc} erwartet war 10"
    fi

    rm -rf "${tmpdir}"
}

# ===========================================================================
# T07  Positiv — render_network_lan() erzeugt "set network.lan=interface"
# ===========================================================================
test_T07_render_network_lan_creates_section() {
    setup_stubs

    # prefix_to_mask() wird von render_network_lan() benötigt
    eval "$(sed -n '/^prefix_to_mask()/,/^}$/p' "${PROVISION}")"
    eval "$(sed -n '/^render_network_lan()/,/^}$/p' "${PROVISION}")"

    local batch; batch="$(mktemp)"

    # Stub-Umgebung für die Funktion
    CFG_IP_LAN_SUBNET="192.168.20.0/24"
    CFG_VLAN_LAN="20"
    CFG_DNS_PRIMARY="1.1.1.1"
    CFG_DNS_SECONDARY="8.8.8.8"
    # Überschreibe uci_batch_add als Shell-Funktion
    uci_batch_add() { printf '%s\n' "$*" >> "${batch}"; }

    render_network_lan

    if grep -q "set network.lan=interface" "${batch}"; then
        _pass "T07 render_network_lan: 'set network.lan=interface' im UCI-Batch vorhanden"
    else
        _fail "T07 render_network_lan: 'set network.lan=interface' fehlt im UCI-Batch"
    fi

    # Zusatz: device-Zeile muss NACH der Interface-Deklaration stehen
    local pos_iface pos_dev
    pos_iface="$(grep -n "network.lan=interface"         "${batch}" | head -1 | cut -d: -f1)"
    pos_dev="$(  grep -n "network.lan.device"            "${batch}" | head -1 | cut -d: -f1)"
    if [ -n "${pos_iface}" ] && [ -n "${pos_dev}" ] && [ "${pos_iface}" -lt "${pos_dev}" ]; then
        _pass "T07 Reihenfolge: =interface vor .device im Batch korrekt"
    else
        _fail "T07 Reihenfolge: =interface (Z${pos_iface}) muss vor .device (Z${pos_dev}) stehen"
    fi

    rm -f "${batch}"
}

# ===========================================================================
# T08  Edge — check_logread_errors: sed extrahiert nur Zeilen nach skip=N
# ===========================================================================
test_T08_logread_sed_skip() {
    setup_stubs

    # Logread-Stub: 5 harmlose Zeilen, dann Fehlerzeile, dann weitere Zeile
    cat > "${STUBS_DIR}/logread" <<'EOF'
#!/bin/sh
printf 'info1\ninfo2\ninfo3\ninfo4\ninfo5\nhostapd: FAILED to set beacon parameters\ninfo7\n'
EOF
    chmod +x "${STUBS_DIR}/logread"

    local skip=5
    local errors
    errors="$(logread 2>/dev/null | \
        sed -n "$((skip + 1)),\$p" | \
        grep -iE '(hostapd|netifd|wpa_supplicant).*(FAILED|fatal|cannot bind|refused|invalid config|bad key)' | \
        head -20)"

    if [ -n "${errors}" ]; then
        _pass "T08 sed skip=${skip}: hostapd FAILED in Zeile $((skip+1)) korrekt extrahiert"
    else
        _fail "T08 sed skip=${skip}: Fehlerzeile wurde nicht extrahiert"
    fi

    # Negativ-Prüfung: skip=6 → Fehlerzeile ist jetzt VOR dem Schnitt → kein Match
    local errors_miss
    errors_miss="$(logread 2>/dev/null | \
        sed -n "$((skip + 2)),\$p" | \
        grep -iE '(hostapd|netifd|wpa_supplicant).*(FAILED|fatal|cannot bind|refused|invalid config|bad key)' | \
        head -20)"

    if [ -z "${errors_miss}" ]; then
        _pass "T08 sed skip=$((skip+1)): Fehlerzeile vor Schnitt → korrekt kein Match"
    else
        _fail "T08 sed skip=$((skip+1)): Fehlerzeile sollte nicht mehr extrahiert werden"
    fi
}

# ===========================================================================
# Ausführung
# ===========================================================================
printf '=== provision_v3 Test-Runner ===\n'
printf 'Provision: %s\n\n' "${PROVISION}"

test_T01_overlap_same_24
test_T02_overlap_20_contains_24
test_T03_no_overlap_different_24
test_T04_empty_prefix_returns_1
test_T05_no_overlap_20_vs_distant_24
test_T06_validate_no_opkg
test_T07_render_network_lan_creates_section
test_T08_logread_sed_skip

printf '\n=== Ergebnis: %d PASS / %d FAIL ===\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
