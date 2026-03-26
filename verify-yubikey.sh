#!/usr/bin/env bash
# verify-yubikey.sh
# Verifica el estado y funcionamiento de YubiKey con GitHub
# Uso: bash verify-yubikey.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"

ERRORS=0

check_pass() { echo -e "$PASS $*"; }
check_fail() { echo -e "$FAIL $*"; ((ERRORS++)); }
check_warn() { echo -e "$WARN $*"; }
check_info() { echo -e "$INFO $*"; }

echo -e "${BLUE}"
echo "=================================================="
echo "   Verificación de YubiKey"
echo "=================================================="
echo -e "${NC}"

# ── 1. Herramientas requeridas ───────────────────────────────────────────────
echo "── Herramientas instaladas ──"
for cmd in ykman ssh ssh-keygen git; do
    if command -v "$cmd" &>/dev/null; then
        check_pass "$cmd ($(command -v "$cmd"))"
    else
        check_fail "$cmd no encontrado"
    fi
done
echo ""

# ── 2. YubiKey detectada ─────────────────────────────────────────────────────
echo "── YubiKey ──"
if ykman info &>/dev/null 2>&1; then
    check_pass "YubiKey detectada"
    ykman info | grep -E "Device|Serial|Firmware|FIDO2|OpenPGP" | \
        sed 's/^/         /'
else
    check_fail "YubiKey NO detectada (¿está conectada?)"
fi
echo ""

# ── 3. Clave SSH FIDO2 ───────────────────────────────────────────────────────
echo "── Clave SSH FIDO2 ──"
SSH_KEY="$HOME/.ssh/id_ed25519_sk_github"
if [[ -f "$SSH_KEY" ]]; then
    check_pass "Clave privada encontrada: $SSH_KEY"
else
    check_fail "Clave privada NO encontrada: $SSH_KEY"
    check_info "Ejecuta setup-yubikey-github.sh para generarla"
fi

if [[ -f "${SSH_KEY}.pub" ]]; then
    check_pass "Clave pública encontrada: ${SSH_KEY}.pub"
    check_info "Fingerprint: $(ssh-keygen -lf "${SSH_KEY}.pub" 2>/dev/null || echo 'N/A')"
else
    check_fail "Clave pública NO encontrada: ${SSH_KEY}.pub"
fi
echo ""

# ── 4. Configuración SSH ─────────────────────────────────────────────────────
echo "── Configuración SSH ──"
SSH_CONFIG="$HOME/.ssh/config"
if grep -q "github.com" "$SSH_CONFIG" 2>/dev/null; then
    check_pass "~/.ssh/config contiene entrada para github.com"
else
    check_warn "~/.ssh/config no contiene github.com"
fi
echo ""

# ── 5. Configuración Git ─────────────────────────────────────────────────────
echo "── Configuración Git ──"
GPG_FORMAT=$(git config --global gpg.format 2>/dev/null || echo "")
SIGNING_KEY=$(git config --global user.signingkey 2>/dev/null || echo "")
COMMIT_SIGN=$(git config --global commit.gpgsign 2>/dev/null || echo "false")

if [[ "$GPG_FORMAT" == "ssh" ]]; then
    check_pass "gpg.format = ssh"
else
    check_warn "gpg.format = '${GPG_FORMAT}' (esperado: ssh)"
fi

if [[ -n "$SIGNING_KEY" ]]; then
    check_pass "user.signingkey = $SIGNING_KEY"
else
    check_warn "user.signingkey no configurado"
fi

if [[ "$COMMIT_SIGN" == "true" ]]; then
    check_pass "commit.gpgsign = true (firma automática activa)"
else
    check_warn "commit.gpgsign = false (firma automática inactiva)"
fi
echo ""

# ── 6. Prueba de conexión SSH a GitHub ───────────────────────────────────────
echo "── Conexión SSH a GitHub ──"
SSH_TEST_OUTPUT=$(ssh -T -o ConnectTimeout=10 -o BatchMode=yes \
    git@github.com 2>&1 || true)
if echo "$SSH_TEST_OUTPUT" | grep -q "successfully authenticated"; then
    check_pass "Autenticación SSH a GitHub: OK"
    echo "$SSH_TEST_OUTPUT" | sed 's/^/         /'
else
    check_warn "No se pudo verificar la conexión SSH a GitHub"
    check_info "Asegúrate de haber registrado la clave pública en:"
    check_info "  https://github.com/settings/keys"
fi
echo ""

# ── Resultado final ───────────────────────────────────────────────────────────
echo "=================================================="
if [[ "$ERRORS" -eq 0 ]]; then
    echo -e "${GREEN}   Todos los checks pasaron. YubiKey lista.${NC}"
else
    echo -e "${RED}   $ERRORS error(s) encontrados. Revisa los mensajes [FAIL].${NC}"
fi
echo "=================================================="
echo ""
