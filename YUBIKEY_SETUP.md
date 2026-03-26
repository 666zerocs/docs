# Guía de configuración de YubiKey con GitHub

Esta guía explica cómo usar los scripts incluidos para proteger tu cuenta de GitHub con una YubiKey mediante autenticación SSH FIDO2 y firma de commits.

## Requisitos previos

- YubiKey 5 series (con soporte FIDO2)
- Ubuntu / Debian o macOS
- Git instalado
- Cuenta de GitHub

## Archivos incluidos

| Archivo | Descripción |
|---|---|
| `setup-yubikey-github.sh` | Instala dependencias, genera clave SSH FIDO2 y configura Git |
| `verify-yubikey.sh` | Verifica que la YubiKey y las claves estén correctamente configuradas |
| `backup-keys.sh` | Crea un backup cifrado de las claves y la configuración |

## Instalación rápida

```bash
# 1. Clona o actualiza el repositorio
git clone https://github.com/666zerocs/docs.git
cd docs

# 2. Da permisos de ejecución a los scripts
chmod +x setup-yubikey-github.sh verify-yubikey.sh backup-keys.sh

# 3. Conecta la YubiKey al puerto USB

# 4. Ejecuta el setup
bash setup-yubikey-github.sh
```

## Pasos detallados

### 1. Instalar dependencias

El script `setup-yubikey-github.sh` instala automáticamente:
- `yubikey-manager` (`ykman`) — gestión de la YubiKey
- `libfido2` — soporte FIDO2 para SSH
- `gnupg2` — firma GPG (opcional)

### 2. Generar la clave SSH FIDO2

La clave `ed25519-sk` se almacena en la YubiKey. Cuando la usas, la YubiKey pide que toques físicamente el sensor, lo que previene usos no autorizados.

```
~/.ssh/id_ed25519_sk_github      ← referencia a la clave en la YubiKey
~/.ssh/id_ed25519_sk_github.pub  ← clave pública (registrar en GitHub)
```

### 3. Registrar la clave en GitHub

1. Copia la clave pública:
   ```bash
   cat ~/.ssh/id_ed25519_sk_github.pub
   ```
2. Ve a [GitHub → Settings → SSH and GPG keys](https://github.com/settings/keys).
3. Haz clic en **New SSH key**.
4. Pega la clave pública y selecciona el tipo **Authentication Key**.
5. Repite el proceso seleccionando el tipo **Signing Key** para firma de commits.

### 4. Probar la conexión

```bash
ssh -T git@github.com
# Hi 666zerocs! You've successfully authenticated...
```

El LED de la YubiKey parpadeará y deberás tocar el sensor.

### 5. Verificar la configuración

```bash
bash verify-yubikey.sh
```

El script comprueba:
- YubiKey detectada
- Claves SSH presentes
- Configuración SSH y Git correctas
- Conexión SSH a GitHub

### 6. Hacer backup de las claves

```bash
bash backup-keys.sh
```

Crea un archivo `.tar.gpg` cifrado con AES-256 que contiene:
- La referencia a la clave SSH (el material criptográfico reside en la YubiKey)
- La configuración SSH y Git

**Guarda el archivo de backup en un lugar seguro y offline** (disco cifrado, USB, gestor de contraseñas).

## Firma de commits

Con la configuración completada, todos los commits y tags se firman automáticamente con la clave de la YubiKey:

```bash
git commit -m "feat: mi cambio seguro"
# La YubiKey parpadea → toca el sensor
```

Verifica la firma en GitHub con el badge **Verified** en cada commit.

## Solución de problemas

### YubiKey no detectada

```bash
# Comprueba que está conectada
ykman info

# Si falla, verifica que el servicio pcscd esté activo (Linux)
sudo systemctl start pcscd
```

### Error "sign_and_send_pubkey: signing failed"

```bash
# Asegúrate de que el ssh-agent está corriendo
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_sk_github
```

### Regenerar la clave si perdiste la YubiKey

1. Conecta la YubiKey de reemplazo.
2. Borra el archivo de clave anterior: `rm ~/.ssh/id_ed25519_sk_github*`
3. Vuelve a ejecutar `bash setup-yubikey-github.sh`.
4. Registra la nueva clave pública en GitHub.
5. Elimina la clave antigua de GitHub en [Settings → SSH keys](https://github.com/settings/keys).

## Seguridad

- La clave privada **nunca sale de la YubiKey**. El archivo `~/.ssh/id_ed25519_sk_github` es solo una referencia.
- Cada operación criptográfica requiere **presencia física** (tocar el sensor).
- Si sospechas que la YubiKey está comprometida, elimina las claves de GitHub inmediatamente y genera nuevas.

## Referencias

- [Documentación de GitHub sobre claves SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [YubiKey Manager](https://developers.yubico.com/yubikey-manager/)
- [FIDO2 / WebAuthn](https://fidoalliance.org/fido2/)
