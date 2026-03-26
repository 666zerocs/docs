# Guía de seguridad: YubiKey + GitHub

Esta guía explica cómo usar una YubiKey para proteger tu cuenta de GitHub con:

- **2FA hardware** (WebAuthn/FIDO2) como segundo factor de autenticación
- **SSH FIDO2** para autenticar operaciones de git sin contraseña
- **Firma de commits con GPG** para verificar la autoría de tus commits
- **Recuperación** ante pérdida de la YubiKey

---

## Requisitos previos

| Requisito | Detalle |
|-----------|---------|
| YubiKey 5 serie (USB-A o USB-C) | Firmware ≥ 5.2.3 para FIDO2 residente |
| Sistema operativo | Linux (Ubuntu/Debian/Fedora) o macOS |
| Software | `yubikey-manager`, `openssh` ≥ 8.2, `gnupg` ≥ 2.1 |
| Cuenta GitHub | Con acceso a Settings |

---

## 1. Configuración rápida (script automático)

```bash
# 1. Clona el repositorio o descarga los scripts
git pull origin main

# 2. Da permisos de ejecución
chmod +x setup-yubikey-github.sh verify-yubikey.sh backup-keys.sh

# 3. Conecta tu YubiKey al puerto USB-C

# 4. Ejecuta el setup completo
bash setup-yubikey-github.sh

# 5. Verifica que todo funciona
bash verify-yubikey.sh

# 6. Haz un backup cifrado de tus claves
bash backup-keys.sh
```

---

## 2. Configurar YubiKey como 2FA en GitHub

### Pasos manuales

1. Inicia sesión en GitHub
2. Ve a **Settings → Password and authentication**
3. En la sección **Two-factor authentication**, haz clic en **Enable**
4. Elige **Authenticator app** primero (como respaldo)
5. Una vez habilitado el 2FA básico, ve a la sección **Security keys**
6. Haz clic en **Add a security key**
7. Cuando se te pida, toca el sensor de la YubiKey (parpadea en dorado)
8. Asigna un nombre descriptivo (p. ej. `YubiKey-5C-trabajo`)

### Verificar el 2FA con YubiKey

1. Cierra sesión en GitHub
2. Inicia sesión con tu usuario y contraseña
3. Cuando aparezca el prompt de 2FA, toca la YubiKey
4. Deberías iniciar sesión correctamente

> **Tip:** Registra al menos 2 YubiKeys o guarda los códigos de recuperación
> antes de cerrar sesión. Si pierdes el acceso, usa `backup-keys.sh`.

---

## 3. SSH FIDO2 con YubiKey

### ¿Qué es SSH FIDO2?

Con SSH FIDO2, la clave privada se genera **dentro de la YubiKey** y nunca
puede ser extraída. Cada operación SSH requiere que toques físicamente la llave.

### Generar la clave SSH FIDO2

```bash
# Genera una clave ed25519-sk (residente en la YubiKey)
ssh-keygen -t ed25519-sk \
    -C "yubikey-$(hostname)-$(date +%Y%m%d)" \
    -f ~/.ssh/id_ed25519_sk_yubikey \
    -O resident \
    -O verify-required

# Cuando parpadee la YubiKey → tócala
```

| Opción | Descripción |
|--------|-------------|
| `-t ed25519-sk` | Tipo de clave: Ed25519 con FIDO2 |
| `-O resident` | Almacena la credencial en la YubiKey |
| `-O verify-required` | Requiere toque físico para cada uso |

### Registrar la clave SSH en GitHub

```bash
# Muestra tu clave pública
cat ~/.ssh/id_ed25519_sk_yubikey.pub
```

1. Copia el contenido completo
2. Ve a **GitHub → Settings → SSH and GPG keys → New SSH key**
3. Tipo: **Authentication Key**
4. Pega la clave y guarda

### Probar la conexión SSH

```bash
ssh -T git@github.com -i ~/.ssh/id_ed25519_sk_yubikey
# Toca la YubiKey cuando parpadee
# Salida esperada: Hi <usuario>! You've successfully authenticated...
```

### Configurar SSH para usar la YubiKey automáticamente

Añade a `~/.ssh/config`:

```sshconfig
Host github.com
    IdentityFile ~/.ssh/id_ed25519_sk_yubikey
    IdentitiesOnly yes
```

---

## 4. Firma de commits con GPG en YubiKey

### ¿Por qué firmar commits?

La firma GPG permite que GitHub muestre el badge **Verified** en tus commits,
garantizando que el commit fue hecho por quien dice ser el autor.

### Generar clave GPG

```bash
# Genera una clave Ed25519 moderna
gpg --batch --gen-key <<EOF
Key-Type: EDDSA
Key-Curve: Ed25519
Subkey-Type: ECDH
Subkey-Curve: Curve25519
Name-Real: Tu Nombre
Name-Email: tu@email.com
Expire-Date: 2y
%no-protection
%commit
EOF
```

### Obtener el ID de tu clave

```bash
gpg --list-secret-keys --keyid-format LONG tu@email.com
# Ejemplo de salida:
# sec   ed25519/ABCD1234EFGH5678 2024-01-01 [SC]
# El ID es la parte después de la barra: ABCD1234EFGH5678
```

### Registrar la clave GPG en GitHub

```bash
# Exportar clave pública
gpg --armor --export ABCD1234EFGH5678
```

1. Copia la clave (incluyendo `-----BEGIN PGP PUBLIC KEY BLOCK-----`)
2. Ve a **GitHub → Settings → SSH and GPG keys → New GPG key**
3. Pega la clave y guarda

### Configurar git para firmar automáticamente

```bash
# Configura el ID de tu clave
git config --global user.signingkey ABCD1234EFGH5678

# Activa la firma automática en todos los commits
git config --global commit.gpgsign true

# Especifica usar GPG
git config --global gpg.program gpg
```

### Verificar que los commits se firman

```bash
# Haz un commit de prueba
git commit --allow-empty -m "test: verificar firma GPG"

# Verifica la firma
git log --show-signature -1
# Debes ver: gpg: Good signature from "Tu Nombre <tu@email.com>"
```

---

## 5. Guía de recuperación

### Escenario 1: Perdiste la YubiKey

1. Accede a GitHub con tus **códigos de recuperación** (generados por `backup-keys.sh`)
2. Ve a **Settings → Password and authentication → Two-factor authentication**
3. En **Security keys**, elimina la YubiKey perdida
4. Si tienes una YubiKey de respaldo, regístrala
5. Genera nuevas claves SSH FIDO2 con la nueva YubiKey:
   ```bash
   ssh-keygen -t ed25519-sk -f ~/.ssh/id_ed25519_sk_yubikey_new ...
   ```

### Escenario 2: Restaurar el backup cifrado

```bash
# Descifrar y extraer el backup
gpg --decrypt ~/yubikey-backup-*.tar.gz.gpg | tar -xzf - -C ~/

# Importar claves GPG
gpg --import ~/yubikey-backup-*/gpg-public-keys.asc
gpg --import-ownertrust ~/yubikey-backup-*/gpg-ownertrust.txt

# Ver los códigos de recuperación
cat ~/yubikey-backup-*/recovery-codes.txt
```

### Escenario 3: Nueva máquina con YubiKey existente

Si usaste `-O resident` al generar la clave SSH, puedes recuperarla directamente:

```bash
# Recuperar credencial residente de la YubiKey
ssh-keygen -K
# Crea id_ed25519_sk_rk y id_ed25519_sk_rk.pub en el directorio actual
```

### Escenario 4: Restablecer PIN de la YubiKey

```bash
# Ver intentos restantes
ykman fido info

# Cambiar PIN
ykman fido access change-pin

# Si bloqueada, resetear FIDO2 (⚠ BORRA TODAS LAS CREDENCIALES FIDO2)
ykman fido reset
```

> ⚠ **Advertencia:** `ykman fido reset` elimina TODAS las credenciales FIDO2
> almacenadas en la YubiKey. Solo úsalo como último recurso.

---

## 6. Referencia rápida de comandos

```bash
# Ver estado de YubiKey
ykman info

# Listar credenciales FIDO2 almacenadas
ykman fido credentials list

# Ver claves SSH cargadas
ssh-add -l

# Ver claves GPG
gpg --list-secret-keys --keyid-format LONG

# Probar SSH con GitHub
ssh -T git@github.com

# Verificar firma del último commit
git log --show-signature -1

# Ver configuración de git
git config --global --list | grep -E "sign|gpg"
```

---

## 7. Mejores prácticas de seguridad

- **Registra 2 YubiKeys** y guarda la segunda en un lugar seguro
- **Guarda los códigos de recuperación** impresos, no solo digitales
- **Usa PIN** en la YubiKey (`ykman fido access change-pin`)
- **Habilita touch** requerido para todas las operaciones (`-O verify-required`)
- **Rota las claves** cada 2 años
- **Verifica el backup** periódicamente ejecutando `bash backup-keys.sh`
- **Nunca compartas** tu YubiKey ni la dejes sin vigilancia

---

## Scripts incluidos

| Script | Descripción |
|--------|-------------|
| `setup-yubikey-github.sh` | Configuración automática completa |
| `verify-yubikey.sh` | Verifica el estado de seguridad |
| `backup-keys.sh` | Crea backup cifrado de claves |

```bash
# Permisos de ejecución
chmod +x setup-yubikey-github.sh verify-yubikey.sh backup-keys.sh
```
