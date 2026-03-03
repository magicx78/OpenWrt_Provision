#!/bin/ash
# tests/run.sh - provision_v3 Test-Runner (BusyBox/ash)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVISION="${SCRIPT_DIR}/../provision_v3"
STUBS_DIR="${SCRIPT_DIR}/stubs"
PASS=0; FAIL=0

_pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
_fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

assert_exit() {
    local label="$1" expected="$2"; shift 2
    local actual
    "$@" >/dev/null 2>&1; actual=$?
    [ "${actual}" -eq "${expected}" ] && _pass "${label} (exit=${expected})" \
        || _fail "${label} (exit=${actual}, erwartet=${expected})"
}

assert_output_contains() {
    local label="$1" pattern="$2"; shift 2
    local out; out="$("$@" 2>&1)"
    echo "${out}" | grep -qE "${pattern}" \
        && _pass "${label}" || _fail "${label} (Pattern '${pattern}' nicht gefunden in: ${out})"
}

setup_stubs() {
    mkdir -p "${STUBS_DIR}"

    # opkg stub
    cat > "${STUBS_DIR}/opkg" <<'STUB'
#!/bin/sh
[ "$1" = "list-installed" ] && {
    echo "${STUB_OPKG_OUTPUT:-wpad-openssl - 2024}"
    exit 0
}
exit 0
STUB

    # uci stub
    cat > "${STUBS_DIR}/uci" <<'STUB'
#!/bin/sh
case "$*" in
    "show wireless"*) echo "wireless.radio0=wifi-device"; echo "wireless.radio0.band=5g";;
    "-q get wireless.radio0.band") echo "5g";;
    "-q get wireless.radio1.band") echo "2g";;
    *) true;;
esac
exit 0
STUB

    # ubus stub
    cat > "${STUBS_DIR}/ubus" <<'STUB'
#!/bin/sh
case "$*" in
    "list"*) echo "network"; echo "network.wireless";;
    "call network.wireless status"*) printf '{"radio0":{"up":true,"mode":"ap"}}\n';;
    *) true;;
esac
exit 0
STUB

    # iw stub
    cat > "${STUBS_DIR}/iw" <<'STUB'
#!/bin/sh
case "$*" in
    "reg get"*) echo "country DE: DFS-ETSI";;
    "list"*)    echo "Band 1:"; echo "  Frequencies:"; echo "    * 5180 MHz [36]";;
    *) true;;
esac
exit 0
STUB

    # logread stub
    cat > "${STUBS_DIR}/logread" <<'STUB'
#!/bin/sh
printf "%s\n" ${STUB_LOGREAD_LINES:-"line1 line2 line3"}
STUB

    # wifi stub
    cat > "${STUBS_DIR}/wifi" <<'STUB'
#!/bin/sh
exit 0
STUB

    # jsonfilter stub
    cat > "${STUBS_DIR}/jsonfilter" <<'STUB'
#!/bin/sh
echo "${STUB_JF_VAL:-}"
exit 0
STUB

    # sha256sum stub
    cat > "${STUBS_DIR}/sha256sum" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do
    echo "aabbccdd1234  $1"
    shift
done
exit 0
STUB

    chmod +x "${STUBS_DIR}"/*
    export PATH="${STUBS_DIR}:${PATH}"
}

# =============================================================================
# UNIT: subnets_overlap() extrahieren und direkt testen
# =============================================================================
load_subnets_overlap() {
    eval "$(sed -n '/^subnets_overlap()/,/^}$/p' "${PROVISION}")"
}

# TEST 1 (Positiv): gleiche /24-Subnets überlappen sich
test_subnets_overlap_match_24() {
    load_subnets_overlap
    subnets_overlap "192.168.1.0/24" "192.168.1.0/24" \
        && _pass "T01 subnets_overlap: gleiche /24 erkennt Überlappung (rc=0)" \
        || _fail "T01 subnets_overlap: gleiche /24 sollte überlappen"
}

# TEST 2 (Positiv): /20 überlappt /24
test_subnets_overlap_20_contains_24() {
    load_subnets_overlap
    subnets_overlap "10.0.16.0/20" "10.0.20.0/24" \
        && _pass "T02 subnets_overlap: /20 enthält /24 → Überlappung erkannt" \
        || _fail "T02 subnets_overlap: /20 vs /24 sollte Überlappung sein"
}

# TEST 3 (Negativ): verschiedene /24-Subnets überlappen sich NICHT
test_subnets_overlap_no_match() {
    load_subnets_overlap
    subnets_overlap "192.168.1.0/24" "192.168.2.0/24" \
        && _fail "T03 subnets_overlap: verschiedene /24 sollte NICHT überlappen" \
        || _pass "T03 subnets_overlap: verschiedene /24 korrekt getrennt (rc=1)"
}

# TEST 4 (Edge): leeres pfx1 → return 1 (Fix-Verifikation)
test_subnets_overlap_empty_pfx() {
    load_subnets_overlap
    subnets_overlap "192.168.1.0" "192.168.1.0/24" \
        && _fail "T04 subnets_overlap: leeres pfx1 sollte return 1 liefern (Bug!)" \
        || _pass "T04 subnets_overlap: leeres pfx1 korrekt return 1"
}

# TEST 5 (Edge): /20 vs entferntes /24 — keine Überlappung
test_subnets_overlap_20_no_24() {
    load_subnets_overlap
    subnets_overlap "10.0.16.0/20" "10.0.32.0/24" \
        && _fail "T05 subnets_overlap: 10.0.16/20 vs 10.0.32/24 sollte NICHT überlappen" \
        || _pass "T05 subnets_overlap: /20 vs entferntes /24 korrekt getrennt"
}

# =============================================================================
# INTEGRATION: validate_packages ohne opkg → Fehlermeldung
# =============================================================================

# TEST 6 (Negativ): opkg fehlt → klare Fehlermeldung
test_validate_no_opkg() {
    setup_stubs
    rm -f "${STUBS_DIR}/opkg"
    local tmpdir; tmpdir="$(mktemp -d)"
    cat > "${tmpdir}/master.json" <<'JSON'
{"regdomain":"DE","country":"DE","radios":{"radio5g":{"band":"5g","channel":"36","htmode":"VHT80","txpower":"20","disabled":"0"},"radio2g":{"band":"2g","channel":"6","htmode":"HT20","txpower":"20","disabled":"0"}},"ssids":{"main":"Test","guest":"Guest","mesh":"Mesh"},"passphrases":{"main":"Pass1!","guest":"Pass2!","mesh":"Pass3!"},"encryption_policy":"sae","roaming":{"mobility_domain":"ab12","ft_over_ds":"1","r0kh":[],"r1kh":[]},"vlans":{"mgmt":"10","lan":"20","guest":"30"},"ip_plan":{"mgmt_subnet":"10.0.10.0/24","lan_subnet":"192.168.20.0/24","guest_subnet":"192.168.30.0/24","dns_primary":"1.1.1.1","dns_secondary":"8.8.8.8"},"nodes":[{"id":"01","hostname":"r01","mgmt_ip":"10.0.10.1","role":"ap_roaming","master_ap_ip":"","master_ap_bssid":""}]}
JSON
    local out rc
    rc=0
    out="$(PROVISION_DIR="${tmpdir}" MASTER_JSON="${tmpdir}/master.json" \
        ash "${PROVISION}" --node-id 01 --profile ap_roaming --validate-only 2>&1)" || rc=$?
    echo "${out}" | grep -qiE "opkg.*nicht gefunden|opkg.*not found" \
        && _pass "T06 opkg fehlt → klare Fehlermeldung ausgegeben" \
        || _fail "T06 opkg fehlt → Meldung erwartet, bekommen: ${out}"
    [ "${rc}" -ne 0 ] \
        && _pass "T06 opkg fehlt → Exit != 0 (rc=${rc})" \
        || _fail "T06 Exit-Code sollte != 0 sein, bekommen: ${rc}"
    rm -rf "${tmpdir}"
}

# =============================================================================
# INTEGRATION: render_network_lan erzeugt "set network.lan=interface"
# =============================================================================

# TEST 7 (Positiv): UCI-Batch enthält "set network.lan=interface"
test_render_network_lan_creates_section() {
    setup_stubs
    eval "$(sed -n '/^prefix_to_mask()/,/^}$/p' "${PROVISION}")"
    eval "$(sed -n '/^render_network_lan()/,/^}$/p' "${PROVISION}")"

    local UCI_BATCH_FILE
    UCI_BATCH_FILE="$(mktemp)"
    CFG_IP_LAN_SUBNET="192.168.20.0/24"
    CFG_VLAN_LAN="20"
    CFG_DNS_PRIMARY="1.1.1.1"
    CFG_DNS_SECONDARY="8.8.8.8"
    uci_batch_add() { echo "$*" >> "${UCI_BATCH_FILE}"; }

    render_network_lan

    grep -q "set network.lan=interface" "${UCI_BATCH_FILE}" \
        && _pass "T07 render_network_lan: 'set network.lan=interface' im Batch vorhanden" \
        || _fail "T07 render_network_lan: 'set network.lan=interface' fehlt im Batch"
    rm -f "${UCI_BATCH_FILE}"
}

# =============================================================================
# UNIT: check_logread_errors sed-Extraktion
# =============================================================================

# TEST 8 (Edge): sed extrahiert nur neue Zeilen seit Baseline
test_check_logread_errors_sed_extraction() {
    setup_stubs
    cat > "${STUBS_DIR}/logread" <<'STUBEOF'
#!/bin/sh
printf '%s\n' info1 info2 info3 info4 info5 "hostapd: FAILED to set beacon parameters" info7
STUBEOF
    chmod +x "${STUBS_DIR}/logread"

    local skip=5
    local errors
    errors="$(logread 2>/dev/null | \
        sed -n "$((skip + 1)),\$p" | \
        grep -iE '(hostapd|netifd|wpa_supplicant).*(FAILED|fatal|cannot bind|refused|invalid config|bad key)' | \
        head -20)"

    [ -n "${errors}" ] \
        && _pass "T08 logread sed-Extraktion: hostapd FAILED nach skip=${skip} gefunden" \
        || _fail "T08 logread sed-Extraktion: Fehler-Zeile nicht extrahiert"
}

# =============================================================================
# RUN
# =============================================================================
echo "=== provision_v3 Tests ==="
test_subnets_overlap_match_24
test_subnets_overlap_20_contains_24
test_subnets_overlap_no_match
test_subnets_overlap_empty_pfx
test_subnets_overlap_20_no_24
test_validate_no_opkg
test_render_network_lan_creates_section
test_check_logread_errors_sed_extraction

echo ""
echo "=== Ergebnis: ${PASS} PASS / ${FAIL} FAIL ==="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
