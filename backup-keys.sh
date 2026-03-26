#!/usr/bin/env bash
# backup-keys.sh
# Crea backup cifrado de claves SSH y configuración de YubiKey
# Uso: bash backup-keys.sh [--output /ruta/backup]

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

# ── Directorio de destino (override con --output) ───────────────────────────
BACKUP_DIR="$HOME/yubikey-backup-$(date +%Y%m%d-%H%M%S)"
if [[ "${1:-}" == "--output" && -n "${2:-}" ]]; then
    BACKUP_DIR="$2"
fi

echo -e "${BLUE}"
echo "=================================================="
echo "   Backup de Claves YubiKey / GitHub"
echo "=================================================="
echo -e "${NC}"

# ── Verificar gpg disponible ─────────────────────────────────────────────────
if ! command -v gpg &>/dev/null; then
    error "gpg no encontrado. Instala gnupg2 e intenta de nuevo."
fi

# ── Crear directorio temporal de trabajo ────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/ssh"
mkdir -p "$WORK_DIR/git"

info "Recopilando archivos a respaldar..."

# ── Copiar claves SSH ─────────────────────────────────────────────────────────
SSH_KEY="$HOME/.ssh/id_ed25519_sk_github"
if [[ -f "$SSH_KEY" ]]; then
    cp "$SSH_KEY"     "$WORK_DIR/ssh/id_ed25519_sk_github"
    success "Clave privada SSH copiada"
else
    warn "Clave privada SSH no encontrada (se omite): $SSH_KEY"
fi

if [[ -f "${SSH_KEY}.pub" ]]; then
    cp "${SSH_KEY}.pub" "$WORK_DIR/ssh/id_ed25519_sk_github.pub"
    success "Clave pública SSH copiada"
fi

if [[ -f "$HOME/.ssh/config" ]]; then
    cp "$HOME/.ssh/config" "$WORK_DIR/ssh/config.bak"
    success "Configuración SSH copiada"
fi

# ── Exportar configuración Git ────────────────────────────────────────────────
if command -v git &>/dev/null; then
    git config --global --list > "$WORK_DIR/git/gitconfig_global.txt" 2>/dev/null || true
    success "Configuración global de Git exportada"
fi

# ── Generar nota de información de YubiKey ───────────────────────────────────
{
    echo "# Backup YubiKey — $(date --utc '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    echo "## Información de YubiKey"
    if command -v ykman &>/dev/null && ykman info &>/dev/null 2>&1; then
        ykman info
    else
        echo "(ykman no disponible o YubiKey no conectada)"
    fi
    echo ""
    echo "## Claves SSH incluidas"
    for f in "$WORK_DIR/ssh"/*.pub; do
        [[ -f "$f" ]] && echo "- $(basename "$f"): $(ssh-keygen -lf "$f" 2>/dev/null || echo 'N/A')"
    done
    echo ""
    echo "## Notas de recuperación"
    echo "- La clave ed25519-sk requiere la YubiKey física para funcionar."
    echo "- Si pierdes la YubiKey, genera una nueva clave y regístrala en GitHub."
    echo "- Guarda este backup en un lugar SEGURO y OFFLINE (disco cifrado, USB)."
} > "$WORK_DIR/BACKUP_INFO.md"

# ── Crear archivo tar cifrado con gpg (cifrado simétrico) ────────────────────
ARCHIVE="$WORK_DIR/yubikey-backup.tar"
tar -cf "$ARCHIVE" -C "$WORK_DIR" ssh git BACKUP_INFO.md
success "Archivo tar creado"

echo ""
warn "IMPORTANTE: Se te pedirá una contraseña para cifrar el backup."
warn "Guarda esa contraseña en un gestor de contraseñas (ej. Bitwarden, 1Password)."
echo ""

ENCRYPTED_ARCHIVE="${ARCHIVE}.gpg"
gpg --symmetric \
    --cipher-algo AES256 \
    --compress-algo ZLIB \
    --output "$ENCRYPTED_ARCHIVE" \
    "$ARCHIVE"

# ── Mover al destino final ────────────────────────────────────────────────────
mkdir -p "$(dirname "$BACKUP_DIR")"
mv "$ENCRYPTED_ARCHIVE" "${BACKUP_DIR}.tar.gpg"

echo ""
echo -e "${GREEN}=================================================="
echo "   Backup completado"
echo "=================================================="
echo -e "${NC}"
success "Backup guardado en: ${BACKUP_DIR}.tar.gpg"
echo ""
echo "Para restaurar:"
echo "  gpg --decrypt ${BACKUP_DIR}.tar.gpg | tar -xv"
echo ""
warn "Guarda el backup en un lugar SEGURO y OFFLINE."
warn "NUNCA subas este archivo a un repositorio público."
echo ""
