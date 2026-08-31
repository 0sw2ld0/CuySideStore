# TrollStore — Investigación de Seguridad y Pruebas en tus Apps

> **Propósito:** Guía defensiva para entender cómo TrollStore explota vulnerabilidades del sistema iOS y cómo probar si tus apps son vulnerables a firmas fraudulentas, parcheo de binarios y bypass de verificaciones de integridad.

---

## 1. ¿Qué es TrollStore?

TrollStore es una herramienta de instalación permanente de apps **sin jailbreak** que explota vulnerabilidades en el proceso de verificación de firmas de iOS. No es un jailbreak: no modifica el kernel ni el sistema de archivos raíz. En su lugar, abusa de la lógica de confianza de iOS para instalar apps **con cualquier entitlement** y **sin verificación de firma válida**.

**Versiones de iOS comprometidas (tabla oficial de compatibilidad):**

| Rango de iOS | Estado | Método de instalación |
|---|---|---|
| iOS 13.7 y anteriores | ✅ No afectado | No soportado |
| iOS 14.0 – 14.8.1 | ❌ Comprometido | TrollHelper / TrollHelperOTA |
| iOS 15.0 – 15.5 beta 4 | ❌ Comprometido | TrollHelperOTA |
| iOS 15.5 – 15.6.1 | ❌ Comprometido | TrollInstallerMDC / TrollHelperOTA |
| iOS 15.7 – 15.7.1 | ❌ Comprometido | TrollInstallerMDC |
| iOS 15.7.2 – 15.8 | ❌ Comprometido | TrollHelper |
| iOS 16.0 – 16.1.2 | ❌ Comprometido | TrollInstallerMDC |
| iOS 16.2 – 16.6.1 | ❌ Comprometido | TrollHelper / Misaka |
| iOS 16.7 – 16.7.2 | ✅ Parcheado | No soportado |
| iOS 17.0 (exactamente 17.0) | ❌ Comprometido | TrollHelper (CVE-2023-41994) |
| iOS 17.0.1 y posteriores | ✅ Parcheado | No soportado |

**Resumen:** el rango comprometido es **iOS 14.0 – 16.6.1** (más **iOS 17.0** exacto). Apple parcheó el bug de CoreTrust en **iOS 16.7** y el exploit de firma de iOS 17.0 en **iOS 17.0.1**.

---

## 2. ¿Cómo funciona técnicamente? (El vector de ataque)

### 2.1 El bug de CoreTrust (CVE-2022-26766)

iOS verifica las apps en **dos capas**:

1. **AMFI (Apple Mobile File Integrity)** — verifica que la firma del binario sea válida y que el certificado sea de confianza (Apple o enterprise).
2. **CoreTrust** — verifica que los entitlements del binario no excedan los del perfil de aprovisionamiento.

**El bug:** CoreTrust no verificaba correctamente la relación entre el certificado de firma y los entitlements declarados. Esto permitía:

- Firmar un binario con **cualquier certificado autofirmado** (no necesita ser de Apple ni enterprise).
- Declarar **cualquier entitlement**, incluyendo los reservados para Apple:
  - `com.apple.private.security.no-container` — sin sandbox
  - `com.apple.private.security.storage.AppDataContainers` — acceso a contenedores de otras apps
  - `platform-application` — la app se trata como app del sistema
  - `com.apple.system-task-ports` — acceso a puertos de tareas del sistema

### 2.2 El flujo de instalación de TrollStore

```
┌─────────────────────────────────────────────────────────────┐
│ 1. TrollStore se instala a sí mismo con entitlements         │
│    de "instalación de apps del sistema"                     │
│                                                             │
│ 2. Usa el framework privado MobileInstallationServices      │
│    para instalar IPAs con entitlements arbitrarios          │
│                                                             │
│ 3. El binario instalado NO pasa por verificación de         │
│    App Store ni de MDM                                      │
│                                                             │
│  TrollStore instala la app → AMFI/CoreTrust no rechaza       │
│  la firma → la app corre con entitlements de plataforma       │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 ¿Qué permite hacer TrollStore con TU app?

Si un atacante tiene tu IPA (por ejemplo, de un dump de App Store, de un dispositivo con jailbreak, o de una copia filtrada), puede:

1. **Re-firmar tu app** con un certificado autofirmado y entitlements arbitrarios.
2. **Parchear el binario** de tu app para:
   - Bypass de jailbreak/tamper detection
   - Bypass de verificaciones de licencia/suscripción
   - Inyectar código (dylibs) para hooking de funciones
   - Extraer secretos embebidos (API keys, endpoints)
3. **Distribuir la versión parcheada** vía TrollStore a otros usuarios.

---

## 3. Cómo probar si tu app es vulnerable

### 3.1 Prerrequisitos

- Un dispositivo iOS físico en el rango afectado (iOS 14.0 – 16.6.1, o iOS 17.0 exacto).
- Tu app compilada en modo Release (`.ipa` o desde Xcode).
- TrollStore instalado en el dispositivo de pruebas.
- Herramientas: `ldid`, `codesign`, `class-dump`, `Hopper`/`Ghidra`, `Frida`.

### 3.2 Prueba 1: Instalación de tu IPA vía TrollStore

**Objetivo:** Verificar si tu app se puede instalar y ejecutar sin firma válida de Apple.

```bash
# 1. Exporta tu app como IPA (desde Xcode o con las herramientas de abajo)
# Desde Xcode: Product > Archive > Distribute App > Development

# 2. Copia el IPA al dispositivo con TrollStore
#    (via la app Files, AirDrop, o URL scheme de TrollStore)

# 3. Abre el IPA con TrollStore → Install
```

**Qué observar:**
- ¿La app se instala sin error?
- ¿La app se ejecuta sin crash inmediato?
- ¿Tu app detecta que la firma no es válida? (ver sección 4)

### 3.3 Prueba 2: Parcheo del binario (simulación de ataque)

**Objetivo:** Verificar si un atacante puede modificar tu binario y redistribuirlo.

```bash
# En macOS, extrae el binario del IPA
unzip TuApp.ipa -d TuApp_extraida
cd TuApp_extraida/Payload/TuApp.app

# Verifica la firma original
codesign -dvvv TuApp
codesign --verify --deep --strict TuApp

# Extrae los entitlements originales
codesign -d --entitlements :- TuApp > entitlements.plist

# Extrae los entitlements que un atacante podría inyectar
cat > malicious_entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.private.security.no-container</key>
    <true/>
    <key>platform-application</key>
    <true/>
    <key>com.apple.private.security.storage.AppDataContainers</key>
    <true/>
    <key>application-identifier</key>
    <string>com.tuempresa.TuApp</string>
    <key>com.apple.developer.team-identifier</key>
    <string>XXXXXXXXXX</string>
</dict>
</plist>
EOF

# Re-firma con certificado autofirmado (simula lo que hace TrollStore)
# En macOS genera un certificado autofirmado en Keychain Access
# Luego:
codesign -f -s "Self-Signed Cert" --entitlements malicious_entitlements.plist TuApp

# Empaqueta de nuevo como IPA
mkdir -p Payload
cp -r TuApp Payload/
zip -r TuApp_patched.ipa Payload
```

**Qué observar:**
- ¿Tu app detecta la re-firma en runtime?
- ¿Tu app detecta entitlements inesperados?
- ¿Las verificaciones de integridad (si existen) se pueden bypass?

### 3.4 Prueba 3: Inyección de código (dylib injection)

**Objetivo:** Verificar si tu app es vulnerable a inyección de dylibs.

```bash
# Un atacante puede agregar una dylib maliciosa al IPA
# y modificar el Load Commands del binario para cargarla al inicio.

# Simulación: crea una dylib que hooking funciones de tu app
cat > hook.c << 'EOF'
#include <stdio.h>
#include <substrate.h>

// Hook de una función de tu app (ejemplo: verificación de licencia)
static void (*orig_verificarLicencia)(void);
static void hook_verificarLicencia(void) {
    printf("[HOOK] verificarLicencia fue llamada — bypassing\n");
    // No llamar al original = bypass de la verificación
}

__attribute__((constructor))
static void init(void) {
    MSHookFunction((void *)verificarLicencia, (void *)hook_verificarLicencia, (void **)&orig_verificarLicencia);
}
EOF
clang -dynamiclib hook.c -o hook.dylib -framework CydiaSubstrate

# El atacante agrega la dylib al .app y modifica el LC_LOAD_DYLIB
# del binario principal para que se cargue al inicio.
```

**Qué observar:**
- ¿Tu app valida sus Load Commands al inicio?
- ¿Tienes `DYLD_INSERT_LIBRARIES` bloqueado? (hardened runtime)
- ¿Tu app usa funciones anti-hooking?

### 3.5 Prueba 4: Extracción de secretos embebidos

**Objetivo:** Verificar qué información sensible puede extraer un atacante del binario.

```bash
# Extrae strings del binario
strings TuApp | grep -iE "api[_-]?key|secret|token|password|endpoint|url"

# Busca endpoints internos
strings TuApp | grep -iE "https?://"

# Busca claves de cifrado embebidas
strings TuApp | grep -iE "aes|rsa|key|iv|salt"

# Usa class-dump para ver la estructura de clases (Objective-C)
class-dump TuApp > clases.txt
# Revisa clases con nombres como "LicenseManager", "SecurityManager", etc.

# Desensambla con Hopper/Ghidra para ver la lógica de verificación
```

**Qué observar:**
- ¿Hay API keys hardcodeadas?
- ¿Hay endpoints de backend expuestos?
- ¿La lógica de verificación de licencia es visible en el desensamblado?
- ¿Hay claves de cifrado embebidas que permitan descifrar datos locales?

### 3.6 Prueba 5: Bypass de jailbreak/tamper detection

**Objetivo:** Verificar si las detecciones de tu app pueden ser bypass.

```bash
# Un atacante parchea el binario para que las funciones de detección
# siempre retornen "no jailbroken" o "no tampered".

# Ejemplo: si tu app tiene una función como:
# - (BOOL)isJailbroken { ... }
# El atacante parchea el binario para que siempre retorne NO.

# Herramienta: patcher o edición hexadecimal del binario
# Busca en el desensamblado la función isJailbroken y reemplaza
# el cuerpo con: mov w0, #0 ; ret  (retorna 0 = NO)
```

**Qué observar:**
- ¿Tu detección de jailbreak es una sola función parcheable?
- ¿Tienes múltiples capas de verificación?
- ¿Verificas la integridad del binario desde el servidor?

### 3.7 Prueba 6: Instalación con entitlements de plataforma

**Objetivo:** Verificar qué puede hacer tu app si corre con entitlements elevados.

```bash
# Instala tu app vía TrollStore con entitlements de plataforma:
# - platform-application
# - com.apple.private.security.no-container
# - com.apple.private.security.storage.AppDataContainers

# Luego prueba:
# 1. ¿Puede tu app leer datos de otras apps? (Keychain compartido, archivos)
# 2. ¿Puede tu app acceder a datos del sistema?
# 3. ¿Tu app usa Keychain con protección de acceso que dependa de la firma?
```

**Qué observar:**
- ¿Tu app asume que corre en sandbox y no valida accesos?
- ¿Tu app usa Keychain con `kSecAttrAccessGroup` que un atacante podría suplantar?
- ¿Tu app confía en el bundle ID para autenticación local?

---

## 4. Mitigaciones y defensas

### 4.1 Verificación de firma en runtime

```swift
import Security

func verifyAppSignature() -> Bool {
    // 1. Verificar que el binario está firmado por Apple
    //    (no por un certificado autofirmado)
    
    // 2. Verificar el hash del binario contra un valor esperado
    //    (calculado en build time y verificado en runtime)
    
    // 4. Verificar que los entitlements actuales coinciden con los esperados
    
    // 5. Attestation del servidor: el servidor verifica que el
    //    dispositivo/app es legítimo antes de dar acceso a datos
    return true
}
```

### 4.2 Verificación de integridad del binario

```swift
import CryptoKit

func verifyBinaryIntegrity() -> Bool {
    // Calcular el hash del binario principal en runtime
    // y compararlo contra un hash esperado (embebido de forma segura
    // o verificado contra el servidor).
    
    // NOTA: El hash embebido puede ser parcheado también.
    // La mejor defensa es la verificación desde el servidor (attestation).
    
    return true
}
```

### 4.3 Bloqueo de inyección de dylibs

```swift
// En el Info.plist de tu app:
// <key>com.apple.security.app-sandbox</key> <true/>
// <key>com App Store apps no pueden usar hardened runtime completo,
// pero puedes validar los Load Commands del binario al inicio.

func validateLoadCommands() -> Bool {
    // Leer los Load Commands del binario principal
    // y verificar que no hay dylibs inesperadas cargadas.
    
    // Alternativa: usar _dyld_image_count() y _dyld_get_image_name()
    // para listar las imágenes cargadas y verificar que solo hay
    // frameworks legítimos.
    return true
}
```

### 4.4 Attestation desde el servidor (defensa más fuerte)

```swift
// El servidor verifica que la app es legítima antes de dar acceso:
// 1. App Attest (DeviceCheck) — Apple verifica que la app es genuina
//    y el dispositivo es genuino.
//  App Store apps: usa App Attest de DeviceCheck.
//  https://developer.apple.com/documentation/devicecheck/appattestservice

import DeviceCheck

func attestApp() {
    let service = DCAppAttestService.shared
    service.generateKey { keyId, error in
        // Enviar keyId al servidor → servidor genera challenge
        // → app firma el challenge → servidor verifica con Apple
    }
}
```

**Por qué es la defensa más fuerte:** Incluso si un atacante parchea tu app, no puede falsificar el attestation de Apple. El servidor rechaza peticiones de apps parcheadas.

### 4.5 No confiar en el cliente para seguridad

- **Nunca** pongas lógica de licencia/suscripción solo en el cliente.
- **Nunca** embebas claves de cifrado en el binario.
- **Verifica desde el servidor** todo lo crítico: suscripciones, permisos, feature flags.
- **Usa App Attest** para verificar que la app es genuina.

### 4.6 Defensas adicionales

- **Ofuscación del binario** — dificulta el parcheo (no lo previene).
- **Múltiples verificaciones distribuidas** — no una sola función `isJailbroken()` parcheable.
- **Verificación de hash del binario desde el servidor** — el cliente envía el hash de su binario, el servidor lo compara contra el esperado.
- **Keychain con protección de acceso** — usa `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` y grupos de acceso restringidos.
- **App Attest + DeviceCheck** — verificación criptográfica de que la app es genuina.

---

## 5. Matriz de riesgo

| Vector de ataque | Riesgo | Mitigación principal |
|---|---|---|
| Re-firma con certificado autofirmado | Alto | App Attest + verificación de firma en runtime |
| Parcheo del binario (bypass de licencias) | Alto | Lógica de licencia en el servidor |
| Inyección de dylibs | Alto | Validación de imágenes cargadas + App Attest |
| Extracción de secretos embebidos | Alto | No embeber secretos; usar App Attest |
| Bypass de jailbreak detection | Medio | Múltiples verificaciones + attestation |
| Entitlements elevados (leer datos de otras apps) | Alto | No confiar en sandbox; cifrar datos locales |
| Instalación sin App Store | Medio | App Attest + DeviceCheck |

---

## 6. Herramientas para pruebas

| Herramienta | Uso |
|---|---|
| TrollStore | Instalar IPAs sin firma válida |
| `codesign` | Firmar/verificar binarios |
| `ldid` | Firmar con entitlements arbitrarios (Linux/macOS) |
| `class-dump` | Extraer headers de clases Objective-C |
| Hopper / Ghidra | Desensamblar binarios |
| Frida | Hooking dinámico en runtime |
| Cydia Substrate | Hooking en dispositivos con jailbreak |
| `strings` | Extraer strings del binario |
| `otool` | Inspección de Load Commands |
| `nm` | Listar símbolos del binario |
| App Attest (DeviceCheck) | Defensa: verificación criptográfica |

---

## 7. Checklist de pruebas de seguridad

- [ ] Instalar tu IPA vía TrollStore — ¿se ejecuta sin crash?
- [ ] Re-firmar tu IPA con certificado autofirmado — ¿tu app lo detecta?
- [ ] Parchear el binario para bypass de licencias — ¿es posible?
- [ ] Inyectar dylib maliciosa — ¿se carga sin detección?
- [ ] Extraer strings del binario — ¿hay secretos embebidos?
- [ ] Desensamblar la app — ¿la lógica de verificación es visible?
- [ ] Instalar con entitlements de plataforma — ¿tu app filtra datos?
- [ ] Parchear funciones de detección — ¿se pueden bypass?
- [ ] Verificar App Attest — ¿el servidor rechaza apps parcheadas?
- [ ] Verificar que no hay secretos embebidos en el binario
- [ ] Verificar que la lógica de licencia está en el servidor, no en el cliente

---

## 8. Referencias

- **TrollStore GitHub:** https://github.com/opa334dev/TrollStore
- **CoreTrust bug (CVE-2022-26766):** https://theori.io/research/creating-rce-using-coretrust
- **App Attest (DeviceCheck):** https://developer.apple.com/documentation/devicecheck/appattestservice
- **MacDirtyCow (CVE-2022-46689):** https://github.com/ZhuoyiLi/DirtyCowApps
- **CVE-2023-41994:** https://github.com/opa334dev/TrollStore (issue tracker)
- **OWASP MASVS (Mobile Application Security Verification Standard):** https://mas.owasp.org/masvs/
- **OWASP Mobile Top 10:** https://owasp.org/www-project-mobile-top-10/