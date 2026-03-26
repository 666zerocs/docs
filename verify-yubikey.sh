#!/usr/bin/env bash
# verify-yubikey.sh
# Verifica que YubiKey, claves SSH FIDO2 y GPG estén correctamente configuradas
# Uso: bash verify-yubikey.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

ok()   { echo -e "  ${GREEN}✓${NC} $*"; ((PASS++)); }
warn() { echo -e "  ${YELLOW}!${NC} $*"; ((WARN++)); }
fail() { echo -e "  ${RED}✗${NC} $*"; ((FAIL++)); }

section() {
    echo ""
    echo -e "${BLUE}── $* ──────────────────────────────────────────${NC}"
}

# ─── 1. Verificar YubiKey conectada ──────────────────────────────────────────
check_yubikey_connected() {
    section "YubiKey Hardware"
    if ! command -v ykman &>/dev/null; then
        fail "ykman no instalado. Ejecuta: bash setup-yubikey-github.sh"
        return
    fi
    if ykman info &>/dev/null 2>&1; then
        ok "YubiKey detectada"
        local serial model firmware
        serial=$(ykman info 2>/dev/null | grep "Serial number" | awk '{print $NF}' || echo "N/A")
        model=$(ykman info  2>/dev/null | grep "Device type"   | cut -d: -f2 | xargs || echo "N/A")
        firmware=$(ykman info 2>/dev/null | grep "Firmware"    | cut -d: -f2 | xargs || echo "N/A")
        echo "     Modelo:    ${model}"
        echo "     Serial:    ${serial}"
        echo "     Firmware:  ${firmware}"
    else
        fail "YubiKey NO detectada. Conecta la YubiKey USB-C."
    fi
}

# ─── 2. Validar clave SSH FIDO2 ───────────────────────────────────────────────
check_ssh_key() {
    section "Clave SSH FIDO2"
    local key_file="$HOME/.ssh/id_ed25519_sk_yubikey"

    if [[ -f "${key_file}" ]]; then
        ok "Clave privada SSH encontrada: ${key_file}"
    else
        fail "Clave privada SSH no encontrada en ${key_file}"
        warn "Ejecuta: bash setup-yubikey-github.sh"
    fi

    if [[ -f "${key_file}.pub" ]]; then
        ok "Clave pública SSH encontrada: ${key_file}.pub"
        local key_type
        key_type=$(awk '{print $1}' "${key_file}.pub")
        echo "     Tipo: ${key_type}"
    else
        fail "Clave pública SSH no encontrada en ${key_file}.pub"
    fi

    # Verificar que los permisos del directorio .ssh son correctos
    local ssh_perms
    ssh_perms=$(stat -c "%a" "$HOME/.ssh" 2>/dev/null || stat -f "%A" "$HOME/.ssh" 2>/dev/null || echo "???")
    if [[ "${ssh_perms}" == "700" ]]; then
        ok "Permisos de ~/.ssh correctos (700)"
    else
        warn "Permisos de ~/.ssh son ${ssh_perms}, deben ser 700. Ejecuta: chmod 700 ~/.ssh"
    fi
}

# ─── 3. Validar clave GPG ─────────────────────────────────────────────────────
check_gpg_key() {
    section "Clave GPG"
    if ! command -v gpg &>/dev/null; then
        fail "gpg no instalado"
        return
    fi

    local secret_keys
    secret_keys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep "^sec" | wc -l)

    if [[ "${secret_keys}" -gt 0 ]]; then
        ok "Se encontraron ${secret_keys} clave(s) GPG secreta(s)"
        gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -E "^(sec|uid)" | \
            sed 's/^/     /'
    else
        fail "No se encontraron claves GPG secretas"
        warn "Ejecuta: bash setup-yubikey-github.sh"
    fi

    # Verificar configuración de git
    local git_signing_key
    git_signing_key=$(git config --global user.signingkey 2>/dev/null || echo "")
    if [[ -n "${git_signing_key}" ]]; then
        ok "git user.signingkey configurado: ${git_signing_key}"
    else
        fail "git user.signingkey no configurado"
        warn "Ejecuta: git config --global user.signingkey <KEY_ID>"
    fi

    local git_gpgsign
    git_gpgsign=$(git config --global commit.gpgsign 2>/dev/null || echo "false")
    if [[ "${git_gpgsign}" == "true" ]]; then
        ok "git commit.gpgsign = true"
    else
        warn "git commit.gpgsign no está en true (valor: ${git_gpgsign})"
    fi
}

# ─── 4. Probar autenticación SSH con GitHub ───────────────────────────────────
check_ssh_auth() {
    section "Autenticación SSH con GitHub"
    local key_file="$HOME/.ssh/id_ed25519_sk_yubikey"

    if [[ ! -f "${key_file}" ]]; then
        fail "No se puede probar: clave SSH no encontrada"
        return
    fi

    warn "Probando SSH con GitHub (puede requerir tocar la YubiKey)..."
    local ssh_output
    ssh_output=$(ssh -T git@github.com -i "${key_file}" \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 2>&1 || true)

    if echo "${ssh_output}" | grep -q "successfully authenticated"; then
        ok "Autenticación SSH con GitHub exitosa"
        echo "     ${ssh_output}"
    elif echo "${ssh_output}" | grep -q "Hi "; then
        ok "Autenticación SSH con GitHub exitosa"
        echo "     ${ssh_output}"
    else
        fail "Autenticación SSH con GitHub fallida"
        echo "     Respuesta: ${ssh_output}"
        warn "Asegúrate de haber añadido la clave pública en:"
        warn "https://github.com/settings/ssh/new"
    fi
}

# ─── 5. Verificar FIDO2/WebAuthn (2FA) ───────────────────────────────────────
check_fido2() {
    section "Capacidades FIDO2 de YubiKey"
    if ! command -v ykman &>/dev/null; then
        fail "ykman no disponible"
        return
    fi

    if ykman info &>/dev/null 2>&1; then
        local fido2_status
        fido2_status=$(ykman fido info 2>/dev/null || echo "No disponible")
        if echo "${fido2_status}" | grep -qi "fido2"; then
            ok "FIDO2 habilitado en YubiKey"
        else
            ok "Interfaz FIDO disponible:"
        fi
        echo "${fido2_status}" | sed 's/^/     /'

        local resident_keys
        resident_keys=$(ykman fido credentials list 2>/dev/null | wc -l || echo "0")
        if [[ "${resident_keys}" -gt 0 ]]; then
            ok "Credenciales residentes encontradas: ${resident_keys}"
        else
            warn "No hay credenciales FIDO2 residentes almacenadas"
        fi
    else
        fail "YubiKey no disponible para verificar FIDO2"
    fi
}

# ─── 6. Resumen de estado ─────────────────────────────────────────────────────
print_summary() {
    local total=$((PASS + WARN + FAIL))
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  RESUMEN DE ESTADO DE SEGURIDAD YUBIKEY${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}✓ Verificaciones exitosas:${NC} ${PASS}/${total}"
    echo -e "  ${YELLOW}! Advertencias:${NC}           ${WARN}/${total}"
    echo -e "  ${RED}✗ Fallos:${NC}                 ${FAIL}/${total}"
    echo ""
    if [[ ${FAIL} -eq 0 && ${WARN} -eq 0 ]]; then
        echo -e "  ${GREEN}🔒 Estado: SEGURO - Todo configurado correctamente${NC}"
    elif [[ ${FAIL} -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠  Estado: ADVERTENCIA - Revisa los elementos marcados con !${NC}"
    else
        echo -e "  ${RED}🔓 Estado: ACCIÓN REQUERIDA - Ejecuta bash setup-yubikey-github.sh${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        YubiKey Security Verification                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"

    check_yubikey_connected
    check_ssh_key
    check_gpg_key
    check_ssh_auth
    check_fido2
    print_summary
}

main "$@"
