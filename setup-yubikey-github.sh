#!/usr/bin/env bash
# setup-yubikey-github.sh
# Configura YubiKey para proteger tu cuenta GitHub con SSH FIDO2 y GPG
# Uso: bash setup-yubikey-github.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── 1. Verificar YubiKey conectada ──────────────────────────────────────────
check_yubikey() {
    info "Verificando YubiKey..."
    if ! command -v ykman &>/dev/null; then
        warn "ykman no instalado todavía; se instalará a continuación."
        return 0
    fi
    if ! ykman info &>/dev/null; then
        error "YubiKey no detectada. Conecta tu YubiKey USB-C y vuelve a ejecutar el script."
    fi
    success "YubiKey detectada:"
    ykman info
}

# ─── 2. Instalar dependencias ─────────────────────────────────────────────────
install_deps() {
    info "Instalando dependencias (yubikey-manager, libfido2, openssh, gnupg)..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y yubikey-manager libfido2-dev libfido2-1 \
            openssh-client gnupg scdaemon pcscd pinentry-curses
    elif command -v brew &>/dev/null; then
        brew install ykman libfido2 gnupg pinentry-mac
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y yubikey-manager libfido2 libfido2-devel \
            openssh gnupg2 pcsc-lite
    else
        error "Gestor de paquetes no reconocido. Instala manualmente: yubikey-manager libfido2 gnupg openssh"
    fi
    success "Dependencias instaladas."
}

# ─── 3. Generar clave SSH FIDO2 ───────────────────────────────────────────────
generate_ssh_key() {
    info "Generando clave SSH FIDO2 con YubiKey..."
    local key_file="$HOME/.ssh/id_ed25519_sk_yubikey"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if [[ -f "${key_file}" ]]; then
        warn "La clave SSH FIDO2 ya existe en ${key_file}. Omitiendo generación."
    else
        echo ""
        info "Se te pedirá que toques la YubiKey cuando parpadee..."
        ssh-keygen -t ed25519-sk \
            -C "yubikey-$(hostname)-$(date +%Y%m%d)" \
            -f "${key_file}" \
            -O resident \
            -O verify-required
        success "Clave SSH FIDO2 generada: ${key_file}"
    fi

    echo ""
    info "Clave pública SSH (añádela a GitHub → Settings → SSH keys):"
    echo "────────────────────────────────────────────────────────────"
    cat "${key_file}.pub"
    echo "────────────────────────────────────────────────────────────"
}

# ─── 4. Generar clave GPG en YubiKey ─────────────────────────────────────────
generate_gpg_key() {
    info "Configurando clave GPG para firma de commits..."

    read -r -p "Introduce tu nombre completo (para GPG): " GPG_NAME
    read -r -p "Introduce tu email de GitHub: " GPG_EMAIL

    if gpg --list-secret-keys "${GPG_EMAIL}" &>/dev/null; then
        warn "Ya existe una clave GPG para ${GPG_EMAIL}. Omitiendo generación."
    else
        info "Generando clave GPG Ed25519..."
        gpg --batch --gen-key <<EOF
Key-Type: EDDSA
Key-Curve: Ed25519
Subkey-Type: ECDH
Subkey-Curve: Curve25519
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Expire-Date: 2y
%no-protection
%commit
EOF
        success "Clave GPG generada para ${GPG_EMAIL}."
    fi

    GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG "${GPG_EMAIL}" \
        | grep sec | awk '{print $2}' | cut -d'/' -f2)

    echo ""
    info "Clave pública GPG (añádela a GitHub → Settings → GPG keys):"
    echo "────────────────────────────────────────────────────────────"
    gpg --armor --export "${GPG_KEY_ID}"
    echo "────────────────────────────────────────────────────────────"

    echo "${GPG_KEY_ID}" > "$HOME/.yubikey_gpg_key_id"
}

# ─── 5. Configurar git para firmar commits ────────────────────────────────────
configure_git() {
    info "Configurando git para firmar commits automáticamente..."

    local key_file="$HOME/.ssh/id_ed25519_sk_yubikey"
    local gpg_key_id

    if [[ -f "$HOME/.yubikey_gpg_key_id" ]]; then
        gpg_key_id=$(cat "$HOME/.yubikey_gpg_key_id")
        git config --global user.signingkey "${gpg_key_id}"
        git config --global commit.gpgsign true
        git config --global gpg.program gpg
        success "Git configurado para firmar commits con GPG (key: ${gpg_key_id})."
    else
        warn "No se encontró ID de clave GPG. Configura manualmente con: git config --global user.signingkey <KEY_ID>"
    fi

    # Configurar SSH signing también (alternativa)
    if [[ -f "${key_file}" ]]; then
        git config --global gpg.ssh.allowedSignersFile "$HOME/.ssh/allowed_signers"
        info "SSH signing también disponible con ${key_file}."
    fi

    success "Configuración de git completada."
}

# ─── 6. Instrucciones para registrar en GitHub ───────────────────────────────
print_github_instructions() {
    local key_file="$HOME/.ssh/id_ed25519_sk_yubikey"

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  PRÓXIMOS PASOS: Registrar claves en GitHub${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}1. CLAVE SSH FIDO2:${NC}"
    echo "   a) Ve a: https://github.com/settings/ssh/new"
    echo "   b) Key type: Authentication Key"
    echo "   c) Pega el contenido de:"
    echo "      ${key_file}.pub"
    echo ""
    echo -e "${YELLOW}2. CLAVE GPG:${NC}"
    echo "   a) Ve a: https://github.com/settings/gpg/new"
    echo "   b) Pega la clave GPG pública mostrada arriba"
    echo ""
    echo -e "${YELLOW}3. ACTIVAR 2FA CON YUBIKEY:${NC}"
    echo "   a) Ve a: https://github.com/settings/two_factor_authentication"
    echo "   b) Sección 'Security keys' → 'Add a security key'"
    echo "   c) Toca la YubiKey cuando se indique"
    echo ""
    echo -e "${YELLOW}4. PROBAR CONEXIÓN SSH:${NC}"
    echo "   ssh -T git@github.com -i ${key_file}"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        YubiKey + GitHub Setup Script                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_yubikey
    install_deps
    check_yubikey   # re-check después de instalar ykman
    generate_ssh_key
    generate_gpg_key
    configure_git
    print_github_instructions

    success "¡Setup completado! Lee YUBIKEY_SETUP.md para más detalles."
}

main "$@"
