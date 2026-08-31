# Análisis Detallado: Sideloadly / AltStore / SideStore

> **Propósito:** Entender en profundidad cómo funcionan las tres herramientas de sideloading más populares, qué implicaciones de seguridad tienen para tu app, y cómo detectar instalaciones hechas con ellas.

---

## 1. El mecanismo común: re-firma con Apple ID personal

Las tres herramientas funcionan bajo el mismo principio fundamental:

```
┌─────────────────────────────────────────────────────────────────┐
│  TU IPA ORIGINAL              IPA RE-FIRMADA                    │
│                                                                 │
│  Firmada por:                 Firmada por:                       │
│  Apple (App Store)     →     Apple ID personal del usuario      │
│                                                                 │
│  Perfil:                      Perfil:                           │
│  Distribution                 Free Development (gratuito)        │
│                                                                 │
│  Team ID:                     Team ID:                           │
│  TU_TEAM_ID                   Team ID del Apple ID del usuario   │
│                                                                 │
│  Entitlements:                Entitlements:                      │
│  Completos (push, IAP...)     Limitados (sin push, sin IAP)      │
│                                                                 │
│  Expiración:                  Expiración:                        │
│  Ninguna                      7 días (Apple ID gratuito)         │
│                               365 días (cuenta developer $99/año)│
└─────────────────────────────────────────────────────────────────┘
```

**Punto crítico:** Estas herramientas **no explotan ninguna vulnerabilidad**. Usan el mecanismo legítimo de Apple para instalar apps de desarrollo en dispositivos propios. Por eso funcionan en **todas las versiones de iOS**, incluyendo las más recientes.

---

## 2. Sideloadly

### 2.1 Qué es

Aplicación de escritorio (macOS y Windows) que instala IPAs en dispositivos iOS usando el Apple ID del usuario. Es la herramienta más directa y popular para sideloading individual.

| Característica | Detalle |
|---|---|
| Plataforma | macOS 10.12+, Windows 7+ (32 y 64 bits) |
| Versión actual | v0.60.0 |
| Jailbreak requerido | No |
| Versiones iOS soportadas | iOS 7 hasta iOS 26+ |
| Apple Silicon Macs | Sí (instala apps iOS en M1–M5) |
| Apple TV | Sí (sideloading a tvOS) |
| Precio | Gratis (soportado por Patreon) |

### 2.2 Cómo funciona técnicamente

```
┌────────────┐     ┌──────────────┐     ┌─────────────────┐
│ Sideloadly │     │  Servidores  │     │    Dispositivo   │
│ (Desktop)  │     │   de Apple   │     │      iOS         │
└─────┬──────┘     └──────┬───────┘     └────────┬────────┘
      │                    │                      │
      │ 1. Usuario entra   │                      │
      │    su Apple ID     │                      │
      │───────────────────>│                      │
      │                    │                      │
      │ 2. Pide perfil de  │                      │
      │    aprovisionamiento│                     │
      │<───────────────────│                      │
      │    (mobileconfig)  │                      │
      │                    │                      │
      │ 3. Re-firma el IPA│                      │
      │    con el perfil   │                      │
      │    + certificado   │                      │
      │                    │                      │
      │ 4. Instala via     │                      │
      │    AFC/usbmuxd     │──────────────────────>│
      │                    │                      │
      │                    │            App instalada
      │                    │            (expira en 7 días
      │                    │             si Apple ID gratis)
```

**Pasos detallados:**

1. **Autenticación con Apple:** Sideloadly envía el Apple ID del usuario a los servidores de Apple (mismo flujo que Xcode usa para desarrollo). Requiere contraseña y código 2FA.

2. **Registro del dispositivo:** El UDID del dispositivo se registra en la cuenta de desarrollador del Apple ID (gratis permite hasta 10 dispositivos).

3. **Generación del perfil:** Apple genera un perfil de aprovisionamiento "free development" que incluye:
   - El certificado de firma del Apple ID
   - El UDID del dispositivo
   - El bundle ID de la app (modificado — ver abajo)
   - Entitlements limitados

4. **Re-firma del IPA:** Sideloadly reemplaza la firma original de Apple con la nueva, usando herramientas como `ldid` o `codesign`.

5. **Instalación:** Transfiere el IPA via USB (o Wi-Fi) usando el servicio AFC de iOS.

### 2.3 Limitaciones del Apple ID gratuito

| Límite | Valor |
|---|---|
| Apps activas simultáneamente | 3 por Apple ID |
| Duración de la firma | 7 días |
| Dispositivos registrados | 10 por cuenta |
| Entitlements disponibles | Básicos (sin push, sin IAP, sin iCloud completo) |
| Bundle ID | Se modifica (añade sufijo único) |

### 2.4 Características de Sideloadly

- **Auto-refresh:** Daemon en segundo plano que re-firma apps automáticamente antes de que expiren
- **Wi-Fi sideloading:** Instala sin cable USB (misma red local)
- **Modificación de bundle ID:** Cambia el bundle ID para evitar conflictos con apps existentes
- **Inyección de dylibs:** Permite agregar dylibs al IPA antes de instalar (⚠️ vector de ataque)
- **Cambio de entitlements:** Permite modificar los entitlements del IPA

### 2.5 Implicaciones de seguridad para tu app

1. **La firma original se pierde** — tu app corre con el Team ID del Apple ID del usuario, no el tuyo
2. **El bundle ID cambia** — tu app puede comportarse diferente si depende del bundle ID exacto
3. **Sin App Store receipt** — la instalación no genera el recibo de compra de App Store
4. **Entitlements limitados** — push notifications, IAP, iCloud pueden no funcionar
5. **Inyección de dylibs** — Sideloadly facilita agregar código malicioso al IPA

---

## 3. AltStore

### 3.1 Qué es

Tienda de apps alternativa creada por Riley Testut (desarrollador del emulador Delta). Es la herramienta de sideloading más "amigable" y con mejor UX. Tiene dos versiones con mecanismos completamente diferentes.

| Característica | AltStore Classic | AltStore PAL |
|---|---|---|
| Disponibilidad | Mundial | Solo EU, Japón, Brasil |
| Requiere computadora | Sí (AltServer) | No |
| Mecanismo | Apple ID + AltServer | Marketplace oficial de Apple (DMA) |
| Límite de apps | 3 (Apple ID gratis) | Sin límite de 3 apps |
| Expiración | 7 días (auto-refresh) | 1 año |
| Requiere jailbreak | No | No |
| Open source | Sí | Sí |

### 3.2 AltStore Classic — Cómo funciona

```
┌──────────────┐         ┌──────────────┐         ┌────────────┐
│  AltServer   │         │  Servidores  │         │  AltStore  │
│ (Mac/Windows)│         │   de Apple   │         │  (en iOS)  │
└──────┬───────┘         └──────┬───────┘         └─────┬──────┘
       │                        │                       │
       │ 1. Se ejecuta en la    │                       │
       │    computadora del     │                       │
       │    usuario (background)│                       │
       │                        │                       │
       │ 2. Detecta el iPhone  │                       │
       │    en la misma red Wi-Fi                       │
       │                        │                       │
       │ 3. Cada X horas:       │                       │
       │    - Pide a Apple      │                       │
       │      perfiles nuevos   │                       │
       │───────────────────────>│                       │
       │    - Re-firma AltStore  │                       │
       │      y apps instaladas │                       │
       │                        │                       │
       │ 4. Envía apps re-firmadas│                     │
       │    al iPhone via Wi-Fi  │──────────────────────>│
       │                        │                       │
       │                        │              5. AltStore instala
       │                        │                 y refresca apps
       │                        │                 automáticamente
```

**Componentes:**

- **AltServer (macOS/Windows):** Se ejecuta en la computadora del usuario. Es el que habla con Apple y re-firma las apps. Requiere macOS 11+ o Windows 10+.
- **AltStore (iOS):** La app en el dispositivo. Recibe las apps re-firmadas del AltServer y las instala. Muestra una tienda con apps disponibles.
- **Sistema de "sources":** Cualquiera puede publicar apps hosteando un archivo JSON que describe sus apps. Los usuarios añaden la URL de la source a AltStore.

### 3.3 AltStore PAL — Cómo funciona (diferente)

AltStore PAL usa el marco legal de **Digital Markets Act (DMA)** de la Unión Europea, que obligó a Apple a permitir tiendas de apps alternativas.

```
┌─────────────────────────────────────────────────────────────┐
│  AltStore PAL (EU/Japón/Brasil)                              │
│                                                              │
│  1. Apple certifica AltStore PAL como "marketplace" oficial  │
│     (proceso de revisión de Apple, requiere cuenta de       │
│     desarrollador empresarial y garantía financiera)       │
│                                                              │
│  2. AltStore PAL se instala como una app normal del sistema │
│     — no necesita AltServer ni re-firma con Apple ID        │
│                                                              │
│  3. Las apps que instala NO expiran en 7 días                │
│     — usan el certificado del marketplace                    │
│                                                              │
│  4. Apple cobra comisión por las apps instaladas              │
│     (Core Technology Fee: €0.50 por instalación anual)      │
└─────────────────────────────────────────────────────────────┘
```

**Diferencia clave:** Las apps instaladas via AltStore PAL tienen una firma válida de marketplace, no una firma de desarrollo personal. Esto significa que **no expiran** y tienen entitlements más completos.

### 3.4 Sistema de sources de AltStore

```json
// Ejemplo de un archivo source.json que cualquiera puede hostear
{
    "name": "Mi Source de Apps",
    "identifier": "com.misource.apps",
    "apps": [
        {
            "name": "Mi App",
            "bundleIdentifier": "com.miempresa.miapp",
            "version": "2.1.0",
            "versionDate": "2026-08-31T00:00:00Z",
            "downloadURL": "https://miserver.com/miapp.ipa",
            "size": 15728640,
            "permissions": [
                {
                    "type": "camera",
                    "usageDescription": "Para escanear códigos"
                }
            ]
        }
    ]
}
```

**Riesgo:** Un atacante puede crear una source con tu app parcheada y distribuirla a cualquier usuario de AltStore que añada esa URL.

---

## 4. SideStore

### 4.1 Qué es

Fork de AltStore que **elimina la necesidad de computadora** completamente. Después de la instalación inicial, todo funciona desde el propio dispositivo iOS.

| Característica | Detalle |
|---|---|
| Basado en | Fork de AltStore |
| Requiere computadora | Solo para instalación inicial |
| Después de instalado | Solo Wi-Fi |
| Mecanismo | Servidor "anisette" propio |
| JIT enabler | Incluido (via WireGuard VPN) |
| Open source | Sí (GitHub: SideStore/SideStore) |
| Precio | Gratis |

### 4.2 Cómo funciona técnicamente

La innovación de SideStore es el **servidor anisette** — emula las respuestas de los servidores de Apple para que el propio iPhone pueda generar perfiles de aprovisionamiento sin computadora.

```
┌──────────────────────────────────────────────────────────────┐
│                    DISPOSITIVO iOS (solo)                     │
│                                                              │
│  ┌────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │  SideStore │    │   Servidor   │    │  Servidores de   │  │
│  │  (app)     │───>│   Anisette   │───>│     Apple        │  │
│  └────────────┘    └──────────────┘    └─────────────────┘  │
│                                                              │
│  1. SideStore pide datos "anisette" al servidor              │
│     (datos de dispositivo que Apple espera: one-time         │
│      password, device certificates, etc.)                    │
│                                                              │
│  2. Con esos datos, SideStore se autentica con Apple         │
│     DIRECTAMENTE desde el iPhone                             │
│                                                              │
│  3. Apple genera el perfil de aprovisionamiento              │
│     y SideStore lo usa para re-firmar apps                   │
│                                                              │
│  4. SideStore instala las apps via el framework privado      │
│     de instalación (mismo que usa AltStore)                  │
└──────────────────────────────────────────────────────────────┘
```

**El servidor anisette** es la pieza clave: genera los datos de "Siri data" y certificados de dispositivo que normalmente solo Xcode/AltServer pueden producir. SideStore lo implementa en Rust (proyecto `apple-private-apis` en GitHub).

### 4.3 JIT Enabler (único de SideStore)

SideStore incluye un habilitador de JIT (Just-In-Time compilation) que otras herramientas no ofrecen sin jailbreak:

```
┌────────────────────────────────────────────────────────────┐
│  Cómo funciona el JIT enabler de SideStore                  │
│                                                             │
│  1. SideStore crea un perfil VPN WireGuard local            │
│                                                             │
│  2. El perfil VPN activa el entitlement                     │
│     com.apple.developer.kernel.increased-memory-limit       │
│     y JIT debugging                                         │
│                                                             │
│  3. La app objetivo se lanza con JIT habilitado             │
│     (necesario para emuladores como UTM, DolphiniOS)        │
│                                                             │
│  ⚠️ Esto también permite ejecutar código dinámico           │
│     en apps que normalmente no lo permiten                   │
└────────────────────────────────────────────────────────────┘
```

### 4.4 Apps distribuidas via SideStore

SideStore tiene su propio catálogo de apps verificadas, pero permite instalar **cualquier IPA**. Su catálogo incluye:

- Emuladores (PPSSPP, UTM, DolphiniOS, RetroArch, MeloNX)
- Jailbreaks (unc0ver, Taurine, Odyssey)
- **LiveContainer** — ejecuta apps iOS sin instalarlas realmente
- Utilidades (iSH, iTorrent, StikDebug)

**Nota:** La presencia de **LiveContainer** en su catálogo es relevante para seguridad — permite ejecutar apps dentro de un contenedor sin instalación formal, lo que complica la detección.

---

## 5. Comparación directa

| Aspecto | Sideloadly | AltStore Classic | AltStore PAL | SideStore |
|---|---|---|---|---|
| **Requiere computadora** | Sí (siempre) | Sí (AltServer) | No | Solo instalación inicial |
| **Requiere Wi-Fi** | No (USB) | Sí (mismo network) | No | Sí |
| **Apple ID del usuario** | Sí | Sí | No (marketplace) | Sí |
| **Expiración apps** | 7 días / 1 año | 7 días (auto-refresh) | 1 año | 7 días (auto-refresh) |
| **Límite 3 apps** | Sí | Sí | No | Sí |
| **Instala cualquier IPA** | Sí | Sí (via sources) | Solo apps aprobadas | Sí |
| **Inyección de dylibs** | Sí (feature) | No directo | No | No directo |
| **Modifica entitlements** | Sí (feature) | Limitado | No | Limitado |
| **JIT habilitado** | No | No | No | Sí |
| **Versiones iOS** | 7 – 26+ | 14+ | 17.0+ (EU) | 14+ |
| **Detección de firma alterada** | Fácil | Fácil | Difícil (firma válida) | Fácil |

---

## 6. Vectores de ataque específicos para tu app

### 6.1 Vector 1: Distribución de tu app parcheada

```
Atacante obtiene tu IPA (dump de App Store o filtración)
        │
        ▼
Parchea el binario (bypass de licencia, inyección de código)
        │
        ▼
Distribuye via:
├── Source de AltStore (URL pública)
├── IPA directa para Sideloadly/SideStore
└── Página web con instrucciones
        │
        ▼
Usuarios instalan tu app parcheada con su propio Apple ID
        │
        ▼
Tu app corre con firma del Apple ID del usuario final
(no la tuya) — sin que tú lo sepas
```

### 6.2 Vector 2: Inyección de dylibs con Sideloadly

Sideloadly tiene una feature que facilita la inyección de código:

```
1. Atacante crea una dylib maliciosa que hookea funciones de tu app
2. En Sideloadly: arrastra la dylib al campo "Inject dylibs"
3. Sideloadly modifica el Load Command del binario principal
4. La dylib se carga al iniciar tu app
5. El hook puede: bypass de licencias, extraer datos, redirigir tráfico
```

### 6.3 Vector 3: LiveContainer (via SideStore)

```
LiveContainer ejecuta tu app DENTRO de otra app contenedora:
├── Tu app no se instala realmente — corre en memoria
├── El bundle ID visible es el del contenedor, no el tuyo
├── Las verificaciones de firma ven al contenedor, no a tu app
└── Tu app puede correr con entitlements del contenedor
```

**Esto rompe varias detecciones estándar** porque las APIs de verificación (`SecTaskCreateFromSelf`, bundle ID checks) ven al contenedor, no a tu app real.

---

## 7. Cómo detectar instalaciones de sideloading

### 7.1 Detección 1: Team ID no coincide

```swift
import Security

func isSideloaded() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil),
          let teamId = SecTaskCopyValueForEntitlement(
              task,
              "com.apple.developer.team-identifier" as CFString,
              nil
          ) as? String else {
        return true  // Sin team ID = definitivamente sideloaded
    }
    
    // ⚠️ Reemplaza con TU Team ID real (de Apple Developer Portal)
    let myTeamId = "TU_TEAM_ID_AQUI"
    
    // Si el team ID no es el tuyo, la app fue re-firmada
    return teamId != myTeamId
}
```

**Por qué funciona:** Sideloadly/AltStore/SideStore re-firman con el Apple ID del usuario. El Team ID de un Apple ID personal es diferente al de tu cuenta de desarrollador de empresa.

**Limitación:** Un atacante puede parchear esta función. Úsala como una señal más, no como única defensa.

### 7.2 Detección 2: Bundle ID modificado

```swift
func hasModifiedBundleId() -> Bool {
    let currentBundleId = Bundle.main.bundleIdentifier ?? ""
    
    // Sideloadly a veces añade sufijos al bundle ID
    // AltStore/SideStore usan el bundle ID original pero con
    // perfil de desarrollo
    
    // Verificar contra el bundle ID esperado
    let expectedBundleId = "com.tuempresa.tuapp"
    
    return currentBundleId != expectedBundleId
}
```

### 7.3 Detección 3: Sin App Store receipt

```swift
func hasAppStoreReceipt() -> Bool {
    // Las apps del App Store tienen un recibo firmado por Apple
    // Las apps sideloaded NO lo tienen (o tienen uno inválido)
    
    guard let receiptURL = Bundle.main.appStoreReceiptURL,
          FileManager.default.fileExists(atPath: receiptURL.path) else {
        return false  // Sin recibo = no instalada del App Store
    }
    
    // Verificación adicional: el recibo debe ser válido
    // (en producción, verificar con App Store Server API)
    return true
}
```

**Nota:** Esta detección también se activa para builds de TestFlight y desarrollo. Úsala con cuidado para no bloquear usuarios legítimos.

### 7.4 Detección 4: Entitlements de desarrollo (no producción)

```swift
func hasDevelopmentEntitlements() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else {
        return true
    }
    
    // Los perfiles de desarrollo gratuito tienen entitlements
    // característicos que las apps del App Store no tienen:
    
    // 1. "beta-reports-active" — presente en perfiles de desarrollo
    if SecTaskCopyValueForEntitlement(task, "beta-reports-active" as CFString, nil) != nil {
        return true
    }
    
    // 2. "application-identifier" con formato de desarrollo
    if let appId = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil) as? String {
        // Los perfiles de desarrollo tienen un formato específico
        // que difiere del de distribución
        if appId.hasPrefix("TEAMID.com.") {
            // Formato de desarrollo detectado
            return true
        }
    }
    
    return false
}
```

### 7.5 Detección 5: Perfil de aprovisionamiento embebido

```swift
func hasDevelopmentProvisioningProfile() -> Bool {
    // Las apps del App Store NO tienen perfil embebido
    // Las apps sideloaded SÍ tienen uno (de desarrollo)
    
    guard let profilePath = Bundle.main.path(
        forResource: "embedded",
        ofType: "mobileprovision"
    ) else {
        return false  // Sin perfil = probablemente App Store (bien)
    }
    
    // Hay perfil embebido = instalada via sideloading o desarrollo
    return true
}
```

**Esta es una de las detecciones más fiables:** Las apps del App Store no llevan `embedded.mobileprovision`. Si existe, la app fue instalada por otro mecanismo.

### 7.6 Detección 6: Verificación de firma con SecStaticCodeCheckValidity

```swift
import Foundation
import Security

func verifyCodeSignature() -> Bool {
    // Obtener el path del binario actual
    guard let executablePath = Bundle.main.executablePath else {
        return false
    }
    
    var staticCode: SecStaticCode?
    let status = SecStaticCodeCreateWithPath(
        URL(fileURLWithPath: executablePath) as CFURL,
        [],
        &staticCode
    )
    
    guard status == errSecSuccess, let code = staticCode else {
        return false
    }
    
    // Verificar validez de la firma
    let validateStatus = SecStaticCodeCheckValidity(code, [.basicOnly], nil)
    
    // Si la firma es inválida o fue alterada, falla
    return validateStatus == errSecSuccess
}
```

### 7.7 Estrategia combinada (recomendada)

```swift
class SideloadDetector {
    
    struct SideloadEvidence {
        let wrongTeamId: Bool
        let modifiedBundleId: Bool
        let noAppStoreReceipt: Bool
        let hasDevEntitlements: Bool
        let hasEmbeddedProfile: Bool
        let invalidSignature: Bool
        
        var isSideloaded: Bool {
            // Cualquiera de estas señales fuertes es suficiente
            if wrongTeamId || hasEmbeddedProfile || invalidSignature {
                return true
            }
            // Combinación de señales débiles
            let weakSignals = [noAppStoreReceipt, hasDevEntitlements, modifiedBundleId]
            return weakSignals.filter { $0 }.count >= 2
        }
    }
    
    static func detect() -> SideloadEvidence {
        return SideloadEvidence(
            wrongTeamId: isWrongTeamId(),
            modifiedBundleId: hasModifiedBundleId(),
            noAppStoreReceipt: !hasAppStoreReceipt(),
            hasDevEntitlements: hasDevelopmentEntitlements(),
            hasEmbeddedProfile: hasDevelopmentProvisioningProfile(),
            invalidSignature: !verifyCodeSignature()
        )
    }
    
    private static func isWrongTeamId() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let teamId = SecTaskCopyValueForEntitlement(
                  task, "com.apple.developer.team-identifier" as CFString, nil
              ) as? String else {
            return true
        }
        return teamId != "TU_TEAM_ID_AQUI"
    }
    
    // ... resto de implementaciones ...
}
```

### 7.8 Reportar al servidor (patrón correcto)

```swift
class SecurityReporter {
    
    /// NO bloquear localmente — reportar y dejar que el servidor decida
    func checkAndReport() {
        let evidence = SideloadDetector.detect()
        
        if evidence.isSideloaded {
            // Reportar silenciosamente al servidor
            APIClient.shared.reportSideloadDetection(
                signals: [
                    "wrong_team_id": evidence.wrongTeamId,
                    "modified_bundle_id": evidence.modifiedBundleId,
                    "no_receipt": evidence.noAppStoreReceipt,
                    "dev_entitlements": evidence.hasDevEntitlements,
                    "embedded_profile": evidence.hasEmbeddedProfile,
                    "invalid_signature": evidence.invalidSignature
                ]
            ) { serverDecision in
                // El servidor decide:
                // - Bloquear cuenta
                // - Degradar features
                // - Requerir re-verificación
                // - Solo registrar (telemetría)
                switch serverDecision {
                case .block:
                    self.showBlockedAlert()
                case .degrade:
                    FeatureManager.shared.disablePremiumFeatures()
                case .reverify:
                    self.requestReverification()
                case .logOnly:
                    break  // Solo telemetría
                }
            }
        }
    }
}
```

---

## 8. Diferencias clave vs. TrollStore

| Aspecto | TrollStore | Sideloadly/AltStore/SideStore |
|---|---|---|
| **Mecanismo** | Explota bug de CoreTrust | Usa mecanismo legítimo de Apple |
| **Versiones afectadas** | iOS 14.0–16.6.1, 17.0 | **Todas** (incluyendo iOS 26+) |
| **Entitlements** | Arbitrarios (incluye plataforma) | Limitados al perfil de desarrollo |
| **Expiración** | Nunca (permasigned) | 7 días (gratis) / 1 año (paid) |
| **Requiere Apple ID** | No | Sí (excepto AltStore PAL) |
| **Requiere computadora** | No | Sideloadly: sí / AltStore: sí / SideStore: solo inicial |
| **Detección por Team ID** | Sí (firma alterada) | Sí (firma alterada) |
| **Detección por perfil embebido** | Variable | Sí (siempre presente) |
| **Persistencia** | Permanente | Requiere refresh periódico |
| **Riesgo para tu app** | Alto (entitlements arbitrarios) | Medio (entitlements limitados) |

**Conclusión importante:** Aunque TrollStore es más peligroso (entitlements arbitrarios), las herramientas de sideloading son **más difíciles de eliminar** porque usan mecanismos legítimos de Apple que no pueden parchearse sin romper el desarrollo de apps.

---

## 9. Recomendaciones específicas

### 9.1 Para apps con suscripciones/IAP

```
1. ✅ Verificar TODAS las compras con App Store Server API
   (el cliente envía transaction ID, el servidor verifica con Apple)

2. ✅ Si la app es sideloaded, no hay receipt válido → 
   el servidor rechaza automáticamente

3. ✅ App Attest como capa adicional — las apps sideloaded
   fallan el attestation porque no son la build genuina
```

### 9.2 Para apps con datos sensibles

```
1. ✅ No confiar en el sandbox — cifrar datos localmente
   con claves derivadas del servidor (no embebidas)

2. ✅ Las apps sideloaded tienen el mismo sandbox que las
   normales, pero TrollStore no — asume el peor caso

3. ✅ Session tokens con expiración corta + refresh tokens
   que el servidor puede revocar
```

### 9.3 Para apps con contenido premium

```
1. ✅ El contenido premium NUNCA se descarga al cliente
   hasta que el servidor verifica la suscripción

2. ✅ URLs firmadas con expiración (presigned URLs) para
   contenido premium

3. ✅ Watermarking dinámico — el servidor incrusta el user ID
   en el contenido servido (detecta filtraciones)
```

### 9.4 Monitoreo y telemetría

```javascript
// En el servidor: monitorear señales de sideloading
app.post('/v1/telemetry/security', (req, res) => {
    const signals = req.body.signals;
    
    // Contar instalaciones sideloaded por usuario
    if (signals.wrong_team_id || signals.embedded_profile) {
        db.incrementSideloadCount(req.user.id);
        
        // Si un usuario tiene múltiples señales de sideloading:
        const count = await db.getSideloadCount(req.user.id);
        if (count > 3) {
            // Marcar cuenta para revisión
            await db.flagAccountForReview(req.user.id, 'persistent_sideload');
        }
    }
    
    res.json({ ok: true });
});
```

---

## 10. Referencias

- **Sideloadly:** https://sideloadly.io/
- **AltStore:** https://altstore.io/ / https://faq.altstore.io/
- **AltStore GitHub:** https://github.com/altstoreio/AltStore
- **SideStore:** https://sidestore.io/ / https://docs.sidestore.io/
- **SideStore GitHub:** https://github.com/SideStore/SideStore
- **apple-private-apis (anisette):** https://github.com/SideStore/apple-private-apis
- **LiveContainer:** https://github.com/hugeBlack/LiveContainer
- **Apple — App Store Server API:** https://developer.apple.com/documentation/appstoreserverapi
- **Apple — Third-party marketplaces (DMA):** https://developer.apple.com/support/alternative-app-distribution-in-the-eu/