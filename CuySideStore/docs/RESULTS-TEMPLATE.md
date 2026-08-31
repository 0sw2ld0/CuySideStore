# Plantilla de Resultados — CuySideStore

> Registra aquí los resultados de cada prueba para tener un historial de validación de defensas.

---

## Información de la sesión de pruebas

| Campo | Valor |
|---|---|
| Fecha | 2026-__-__ |
| App probada | _________________ |
| Versión de la app | _________________ |
| Dispositivo | _________________ |
| Versión de iOS | _________________ |
| Certificado usado | _________________ |
| Tester | _________________ |

---

## Prueba 1: Análisis estático

**Comando:** `./scripts/analyze_ipa.sh TuApp.ipa`

| Item | Resultado | Notas |
|---|---|---|
| API keys en strings | ☐ Encontradas ☐ Ninguna | |
| Endpoints expuestos | ☐ Encontrados ☐ Ninguno | |
| Entitlements correctos | ☐ Sí ☐ No | |
| Perfil embebido | ☐ Presente ☐ Ausente | |

**Secretos encontrados (si hay):**
```
(paste aquí)
```

---

## Prueba 2: Re-firma

**Comando:** `./scripts/resign_ipa.sh TuApp.ipa --cert "..."`

| Detección | ¿La app la detectó? | Risk score reportado |
|---|---|---|
| Team ID incorrecto | ☐ Sí ☐ No | |
| Perfil embebido presente | ☐ Sí ☐ No | |
| Entitlements de desarrollo | ☐ Sí ☐ No | |

**Resultado final:**
- ☐ App bloqueó el funcionamiento
- ☐ App reportó al servidor pero funcionó
- ☐ App funcionó normalmente (❌ vulnerable)

---

## Prueba 3: Inyección de dylib

**Comando:** `./scripts/inject_dylib.sh TuApp.ipa --dylib test-dylibs/hook_license.dylib`

| Item | Resultado |
|---|---|
| Mensaje de dylib visible en logs | ☐ Sí (❌ no detectada) ☐ No (✓ bloqueada) |
| App detectó imagen sospechosa | ☐ Sí ☐ No |
| App detectó variables de inyección | ☐ Sí ☐ No |

**Logs relevantes:**
```
(paste de Console.app)
```

---

## Prueba 4: Entitlements de desarrollo

**Comando:** `./scripts/modify_entitlements.sh TuApp.ipa --preset desarrollo`

| Detección | ¿La app la detectó? |
|---|---|
| get-task-allow | ☐ Sí ☐ No |
| beta-reports-active | ☐ Sí ☐ No |

---

## Prueba 5: Entitlements de plataforma (TrollStore)

**Comando:** `./scripts/modify_entitlements.sh TuApp.ipa --preset plataforma`

| Item | Resultado |
|---|---|
| ¿Se pudo instalar? | ☐ Sí ☐ No (esperado: No) |
| Detección de platform-application en código | ☐ Sí ☐ No |

---

## Prueba 6: Validación server-side

| Petición | Respuesta esperada | Respuesta obtenida |
|---|---|---|
| Features con riesgo 80 | 403 | ☐ 403 ☐ 200 (❌) |
| Suscripción sin assertion | 403 | ☐ 403 ☐ 200 (❌) |
| Incidentes registrados | Sí | ☐ Sí ☐ No |

---

## Prueba 7: Flujo App Attest completo

| Paso | Resultado |
|---|---|
| Challenge obtenido | ☐ Sí ☐ No |
| Attestation verificada | ☐ Sí ☐ No |
| Suscripción validada con assertion | ☐ 200 ☐ 403 |

---

## Resumen de hallazgos

### Defensas que funcionan
```
-
```

### Defensas que fallaron (requieren acción)
```
-
```

### Vulnerabilidades críticas encontradas
```
-
```

---

## Acciones correctivas

| # | Acción | Prioridad | Estado |
|---|---|---|---|
| 1 | | Alta/Media/Baja | Pendiente |
| 2 | | Alta/Media/Baja | Pendiente |
| 3 | | Alta/Media/Baja | Pendiente |

---

## Notas adicionales

```
(observaciones, comportamientos inesperados, ideas de mejora)
```