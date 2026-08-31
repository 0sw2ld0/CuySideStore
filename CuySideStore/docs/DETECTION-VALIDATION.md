# Validación de Detecciones — CuySideStore

> Cómo interpretar los resultados de cada detección y qué hacer cuando fallan.

---

## Mapa detección → script de prueba

Cada detección de `TamperDetector.swift` se valida con un script específico:

| Detección | Qué valida | Script que la prueba | Señal esperada |
|---|---|---|---|
| 1. Team ID incorrecto | Firma re-firmada por otro certificado | `resign_ipa.sh` | Team ID ≠ TU_TEAM_ID |
| 2. Bundle ID modificado | Bundle ID alterado | `resign_ipa.sh` (con bundle ID cambiado) | Bundle ID ≠ esperado |
| 3. Sin App Store receipt | Instalación fuera del App Store | Cualquier instalación sideloaded | `appStoreReceiptURL` nil o inexistente |
| 4. Entitlements de desarrollo | Perfil de desarrollo en producción | `modify_entitlements.sh --preset desarrollo` | `get-task-allow` = true |
| 5. Perfil embebido | `embedded.mobileprovision` presente | `resign_ipa.sh` | Archivo existe en el bundle |
| 6. Imágenes sospechosas | Dylib inyectada cargada | `inject_dylib.sh` | `hook_license` en `_dyld_image_count()` |
| 7. Variables de inyección | `DYLD_INSERT_LIBRARIES` etc. | `inject_dylib.sh` (con env vars) | `getenv()` retorna valor |
| 8. Debugger adjunto | Depuración activa | Xcode debugger | `P_TRACED` flag activo |

---

## Interpretación de resultados

### ✅ Detección funciona correctamente

```
[DETECCIÓN 1] Team ID: ABC123DEF — ❌ NO coincide
[DETECCIÓN 5] ❌ embedded.mobileprovision PRESENTE — sideloaded/desarrollo
─── RESULTADO ───
  Risk score: 55/100
  Estado: ❌ COMPROMETIDO
```

**Significa:** Tu app correctamente identifica que fue modificada. La defensa funciona.

**Acción:** Ninguna — la detección está validada.

---

### ⚠️ Detección funciona pero es débil

```
[DETECCIÓN 4] get-task-allow: true — ❌ entitlements de desarrollo
─── RESULTADO ───
  Risk score: 15/100
  Estado: ✓ LIMPIO   ← ¡PROBLEMA! Debería ser COMPROMETIDO
```

**Significa:** La detección funciona pero el umbral (`riskScore >= 30`) es muy alto para esta señal sola.

**Acción:**
1. Revisar los pesos del risk score
2. Considerar bajar el umbral a 15-20
3. O combinar con otras señales antes de decidir

---

### ❌ Detección falla (no detecta)

```
[DETECCIÓN 6] ✓ No hay imágenes sospechosas cargadas (47 imágenes)
```

**Pero instalaste la dylib con `inject_dylib.sh` y ves el mensaje `[CuySideStore] DYLIB INYECTADA CARGADA` en los logs.**

**Significa:** Tu app no está detectando la dylib inyectada.

**Posibles causas y soluciones:**

| Causa | Solución |
|---|---|
| El patrón de búsqueda no coincide | Verifica que "hook_license" está en la lista de `suspiciousPatterns` |
| La detección corre antes de que la dylib se cargue | Mueve la detección a `applicationDidBecomeActive` |
| La dylib se carga después del escaneo | Ejecuta el escaneo múltiples veces |
| Solo escaneas al inicio | Agrega escaneos periódicos o en acciones críticas |

---

## Ajuste de pesos del risk score

Los pesos actuales en `TamperDetector.swift`:

```swift
var riskScore: Int {
    var score = 0
    if wrongTeamId { score += 30 }           // Señal FUERTE
    if modifiedBundleId { score += 10 }      // Señal débil
    if noAppStoreReceipt { score += 10 }      // Señal débil
    if hasDevEntitlements { score += 15 }     // Señal media
    if hasEmbeddedProfile { score += 25 }    // Señal FUERTE
    if suspiciousImages { score += 25 }      // Señal FUERTE
    if injectionEnvVars { score += 15 }      // Señal media
    if debuggerAttached { score += 10 }       // Señal débil
    return min(score, 100)
}
```

**Guía de ajuste:**

| Situación | Ajuste recomendado |
|---|---|
| Demasiados falsos positivos (TestFlight, desarrollo propio) | Bajar pesos de señales débiles (receipt, debugger) |
| Detecciones fallan en pruebas | Subir pesos o bajar umbral |
| Usuarios legítimos bloqueados | Excluir `noAppStoreReceipt` del score (TestFlight también lo activa) |
| Atacantes bypass fácil | Agregar más capas de detección |

**⚠️ IMPORTANTE — Falsos positivos conocidos:**

| Señal | Se activa también en... |
|---|---|
| `noAppStoreReceipt` | TestFlight, builds de desarrollo propias |
| `hasDevEntitlements` | Builds de desarrollo propias (debug) |
| `debuggerAttached` | Desarrollo normal con Xcode |
| `hasEmbeddedProfile` | TestFlight, desarrollo |

**Recomendación:** En builds de desarrollo/TestFlight, desactivar estas detecciones con un flag de compilación:

```swift
#if DEBUG
// Detecciones desactivadas en desarrollo
#else
// Todas las detecciones activas en producción
#endif
```

---

## Estrategia de respuesta según riesgo

El servidor (o la app) debe responder según el nivel de riesgo:

| Risk score | Acción recomendada |
|---|---|
| 0 – 14 | ✓ Funcionamiento normal |
| 15 – 29 | ⚠️ Registrar telemetría, sin restricciones |
| 30 – 54 | ⚠️ Requerir App Attest para endpoints críticos |
| 55 – 69 | ⚠️ Degradar features premium, monitorear cuenta |
| 70 – 100 | ❌ Bloquear acceso a la API, marcar cuenta |

**Nunca bloquear solo en el cliente** — el atacante parchea el bloqueo. Siempre reportar al servidor y dejar que el servidor decida.

---

## Cuándo una detección es "suficiente"

Una detección es suficiente cuando:

1. ✅ **Detecta el ataque en pruebas** (validado con CuySideStore)
2. ✅ **No genera falsos positivos** en usuarios legítimos
3. ✅ **Está combinada con otras capas** (no es la única defensa)
4. ✅ **Reporta al servidor** (no solo bloquea localmente)
5. ✅ **Es difícil de parchear** (verificación distribuida, no una función única)

Si una detección cumple 1 pero no 2-5, es una señal útil pero no una defensa completa.

---

## Próximos pasos después de validar

1. **Integrar las detecciones validadas** en tu app real (no solo la de prueba)
2. **Implementar el reporte al servidor** (endpoint `/v1/telemetry/security`)
3. **Configurar el middleware de riesgo** en tu API real
4. **Implementar App Attest real** (con la clave .p8 de DeviceCheck)
5. **Monitorear incidentes** y ajustar pesos según datos reales
6. **Repetir las pruebas** después de cada release importante