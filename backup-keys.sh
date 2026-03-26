#!/usr/bin/env bash
# backup-keys.sh
# Crea un backup cifrado de las claves SSH y GPG asociadas a YubiKey
# y genera códigos de recuperación de emergencia.
# Uso: bash backup-keys.sh [directorio-destino]

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

BACKUP_DIR="${1:-$HOME/yubikey-backup-$(date +%Y%m%d_%H%M%S)}"
SSH_KEY="$HOME/.ssh/id_ed25519_sk_yubikey"
RECOVERY_FILE="${BACKUP_DIR}/recovery-codes.txt"
CONFIG_FILE="${BACKUP_DIR}/git-config-backup.txt"
ARCHIVE="${BACKUP_DIR}.tar.gz.gpg"

# ─── Verificar dependencias ───────────────────────────────────────────────────
check_deps() {
    for cmd in gpg tar; do
        if ! command -v "${cmd}" &>/dev/null; then
            error "Comando '${cmd}' no encontrado. Instala gnupg y tar."
        fi
    done
}

# ─── Crear directorio de backup ───────────────────────────────────────────────
create_backup_dir() {
    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
    info "Directorio de backup: ${BACKUP_DIR}"
}

# ─── Exportar clave pública SSH ───────────────────────────────────────────────
backup_ssh_keys() {
    info "Haciendo backup de clave pública SSH FIDO2..."

    if [[ -f "${SSH_KEY}.pub" ]]; then
        cp "${SSH_KEY}.pub" "${BACKUP_DIR}/id_ed25519_sk_yubikey.pub"
        success "Clave pública SSH guardada."
    else
        warn "No se encontró clave pública SSH en ${SSH_KEY}.pub"
    fi

    # Nota: la clave privada FIDO2 es un 'handle' al hardware; no contiene
    # el secreto real (que reside en la YubiKey), pero se incluye por conveniencia.
    if [[ -f "${SSH_KEY}" ]]; then
        cp "${SSH_KEY}" "${BACKUP_DIR}/id_ed25519_sk_yubikey.key_handle"
        warn "El handle SSH FIDO2 se ha copiado. Recuerda: el secreto real está en la YubiKey."
    fi
}

# ─── Exportar claves GPG ──────────────────────────────────────────────────────
backup_gpg_keys() {
    info "Exportando claves GPG..."

    if ! command -v gpg &>/dev/null; then
        warn "gpg no disponible; omitiendo backup de GPG."
        return
    fi

    # Clave pública
    gpg --armor --export > "${BACKUP_DIR}/gpg-public-keys.asc" 2>/dev/null
    local pub_count
    pub_count=$(gpg --list-keys 2>/dev/null | grep -c "^pub" || echo 0)
    if [[ "${pub_count}" -gt 0 ]]; then
        success "Claves públicas GPG exportadas (${pub_count} clave(s))."
    else
        warn "No se encontraron claves GPG públicas."
    fi

    # Clave secreta (solo stub si está en tarjeta/YubiKey)
    gpg --armor --export-secret-keys > "${BACKUP_DIR}/gpg-secret-keys.asc" 2>/dev/null || \
        warn "No se pudo exportar claves secretas GPG (pueden estar protegidas en YubiKey)."

    # Anillo de confianza
    gpg --export-ownertrust > "${BACKUP_DIR}/gpg-ownertrust.txt" 2>/dev/null
    success "Trust de GPG exportado."
}

# ─── Guardar configuración git ────────────────────────────────────────────────
backup_git_config() {
    info "Guardando configuración de git..."
    {
        echo "# Backup de configuración git - $(date)"
        echo "# Para restaurar: git config --global <key> <value>"
        echo ""
        git config --global --list 2>/dev/null || echo "(sin configuración global de git)"
    } > "${CONFIG_FILE}"
    success "Configuración de git guardada en ${CONFIG_FILE}."
}

# ─── Generar códigos de recuperación ─────────────────────────────────────────
generate_recovery_codes() {
    info "Generando códigos de recuperación de emergencia..."

    local codes=()
    for _ in $(seq 1 8); do
        # Genera un código de 16 caracteres alfanuméricos
        codes+=("$(LC_ALL=C tr -dc 'A-Z0-9' < /dev/urandom | head -c 4)-$(LC_ALL=C tr -dc 'A-Z0-9' < /dev/urandom | head -c 4)-$(LC_ALL=C tr -dc 'A-Z0-9' < /dev/urandom | head -c 4)-$(LC_ALL=C tr -dc 'A-Z0-9' < /dev/urandom | head -c 4)")
    done

    {
        echo "═══════════════════════════════════════════════════════════"
        echo "  CÓDIGOS DE RECUPERACIÓN DE EMERGENCIA - YUBIKEY GITHUB"
        echo "═══════════════════════════════════════════════════════════"
        echo "Generados: $(date)"
        echo "Host:      $(hostname)"
        echo ""
        echo "INSTRUCCIONES:"
        echo "  - Guarda esta hoja en un lugar seguro OFFLINE."
        echo "  - Cada código es de un solo uso."
        echo "  - Úsalos si pierdes tu YubiKey y no tienes otro 2FA."
        echo "  - Configúralos en: https://github.com/settings/two_factor_authentication"
        echo ""
        echo "CÓDIGOS (un solo uso):"
        for code in "${codes[@]}"; do
            echo "  [ ] ${code}"
        done
        echo ""
        echo "ID de clave GPG principal:"
        gpg --list-secret-keys --keyid-format LONG 2>/dev/null | \
            grep "^sec" | awk '{print $2}' | head -1 || echo "  (ninguna)"
        echo ""
        echo "Clave pública SSH:"
        if [[ -f "${SSH_KEY}.pub" ]]; then
            cat "${SSH_KEY}.pub"
        else
            echo "  (no encontrada)"
        fi
        echo "═══════════════════════════════════════════════════════════"
    } > "${RECOVERY_FILE}"

    success "Códigos de recuperación generados en ${RECOVERY_FILE}."
    warn "¡IMPORTANTE! Imprime o guarda estos códigos en un lugar SEGURO y OFFLINE."
}

# ─── Cifrar el backup ─────────────────────────────────────────────────────────
encrypt_backup() {
    info "Cifrando backup con GPG (passphrase simétrica)..."

    echo ""
    warn "Se te pedirá una passphrase para cifrar el backup."
    warn "Usa una passphrase fuerte y guárdala por separado."
    echo ""

    tar -czf - -C "$(dirname "${BACKUP_DIR}")" "$(basename "${BACKUP_DIR}")" | \
        gpg --symmetric \
            --cipher-algo AES256 \
            --compress-algo none \
            --output "${ARCHIVE}"

    success "Backup cifrado creado: ${ARCHIVE}"

    # Eliminar el directorio sin cifrar
    rm -rf "${BACKUP_DIR}"
    info "Directorio temporal eliminado. Solo queda el archivo cifrado."
}

# ─── Instrucciones de restauración ───────────────────────────────────────────
print_restore_instructions() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  BACKUP COMPLETADO${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Archivo de backup:${NC}"
    echo "  ${ARCHIVE}"
    echo ""
    echo -e "${YELLOW}Para restaurar el backup:${NC}"
    echo "  gpg --decrypt ${ARCHIVE} | tar -xzf - -C ~/"
    echo ""
    echo -e "${YELLOW}Para importar claves GPG restauradas:${NC}"
    echo "  gpg --import ~/yubikey-backup-*/gpg-public-keys.asc"
    echo "  gpg --import-ownertrust ~/yubikey-backup-*/gpg-ownertrust.txt"
    echo ""
    echo -e "${YELLOW}Recomendaciones de seguridad:${NC}"
    echo "  • Copia el archivo cifrado a un dispositivo externo o almacenamiento seguro"
    echo "  • Guarda la passphrase de cifrado en un gestor de contraseñas"
    echo "  • Imprime los códigos de recuperación y guárdalos offline"
    echo "  • Verifica el backup periódicamente"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        YubiKey Key Backup Script                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_deps
    create_backup_dir
    backup_ssh_keys
    backup_gpg_keys
    backup_git_config
    generate_recovery_codes
    encrypt_backup
    print_restore_instructions
}

main "$@"
