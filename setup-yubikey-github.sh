#!/usr/bin/env bash
# setup-yubikey-github.sh
# Configura YubiKey para autenticación SSH y firma GPG con GitHub
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

echo -e "${BLUE}"
echo "=================================================="
echo "   Configuración de YubiKey para GitHub"
echo "=================================================="
echo -e "${NC}"

# ── 1. Verificar YubiKey conectada ──────────────────────────────────────────
info "Verificando YubiKey..."
if ! command -v ykman &>/dev/null; then
    warn "ykman no instalado — instalando dependencias primero..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y yubikey-manager libfido2-dev libfido2-1 \
            openssh-client gnupg2 pinentry-curses
    elif command -v brew &>/dev/null; then
        brew install ykman libfido2 gnupg pinentry-mac
    else
        error "Gestor de paquetes no reconocido. Instala yubikey-manager manualmente."
    fi
fi

if ! ykman info &>/dev/null 2>&1; then
    error "YubiKey no detectada. Conecta tu YubiKey al puerto USB y vuelve a intentarlo."
fi
success "YubiKey detectada:"
ykman info | grep -E "Device|Serial|Firmware" | sed 's/^/         /'

# ── 2. Habilitar FIDO2 y OpenPGP en la YubiKey ──────────────────────────────
info "Verificando aplicaciones habilitadas en YubiKey..."
ykman info | grep -E "FIDO2|OpenPGP" | sed 's/^/         /'

# ── 3. Generar clave SSH FIDO2 ───────────────────────────────────────────────
SSH_KEY="$HOME/.ssh/id_ed25519_sk_github"
info "Generando clave SSH FIDO2 (ed25519-sk)..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$SSH_KEY" ]]; then
    warn "La clave $SSH_KEY ya existe. Omitiendo generación."
else
    echo ""
    info "Toca el sensor de la YubiKey cuando parpadee..."
    ssh-keygen -t ed25519-sk \
        -C "yubikey-github-$(hostname)-$(date +%Y%m%d)" \
        -f "$SSH_KEY" \
        -O resident \
        -O verify-required
    chmod 600 "$SSH_KEY"
    chmod 644 "${SSH_KEY}.pub"
    success "Clave SSH generada: $SSH_KEY"
fi

# ── 4. Configurar ssh-agent ──────────────────────────────────────────────────
info "Configurando SSH Agent..."
SSH_CONFIG="$HOME/.ssh/config"
if ! grep -q "id_ed25519_sk_github" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" <<'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_sk_github
    IdentitiesOnly yes
EOF
    chmod 600 "$SSH_CONFIG"
    success "Configuración SSH actualizada"
else
    warn "Configuración SSH ya existe para github.com"
fi

# ── 5. Configurar Git para firmar commits ────────────────────────────────────
info "Configurando Git para firmar commits con SSH..."
git config --global gpg.format ssh
git config --global user.signingkey "$SSH_KEY.pub"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
success "Git configurado para firmar commits automáticamente"

# ── 6. Mostrar clave pública SSH ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}=================================================="
echo "   CLAVE SSH PÚBLICA — Registra en GitHub"
echo "=================================================="
echo -e "${NC}"
echo "Copia esta clave y añádela en:"
echo "  https://github.com/settings/keys  → 'New SSH key' (tipo: Authentication Key)"
echo ""
cat "${SSH_KEY}.pub"
echo ""
echo "Para firma de commits, también añade la misma clave como 'Signing Key' en:"
echo "  https://github.com/settings/keys  → 'New SSH key' (tipo: Signing Key)"
echo ""

# ── 7. Prueba de conexión (opcional) ─────────────────────────────────────────
info "Para probar la conexión SSH a GitHub ejecuta:"
echo "    ssh -T git@github.com"
echo ""
success "¡Configuración completada!"
echo ""
echo "Próximos pasos:"
echo "  1. Registra la clave pública en GitHub (ver arriba)"
echo "  2. Ejecuta: bash verify-yubikey.sh"
echo "  3. Ejecuta: bash backup-keys.sh"
