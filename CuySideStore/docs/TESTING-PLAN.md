# Plan de Pruebas — CuySideStore

> Guía paso a paso para validar las defensas de tu app contra sideloading, re-firma e inyección de código.

---

## Preparación (una sola vez)

### 1. Instalar dependencias

```bash
brew install ldid libimobiledevice ideviceinstaller insert_dylib
```

### 2. Configurar certificado

```bash
cd CuySideStore/scripts
./setup_test_cert.sh
```

Usa tu certificado "Apple Development" existente (el que Xcode creó). Es exactamente lo que usa Sideloadly.

### 3. Compilar dylibs de prueba

```bash
cd CuySideStore/test-dylibs
make
```

### 4. Preparar la app de prueba

```bash
# Abrir Xcode y crear el proyecto:
open CuySideStore/test-app/
# Crear proyecto nuevo "CuyTestApp" con los archivos .swift existentes
# Seleccionar tu dispositivo físico → Run
```

### 5. Iniciar el servidor de pruebas

```bash
cd CuySideStore/server
npm install
npm start
```

---

## Prueba 1: Análisis estático (sin dispositivo)

**Objetivo:** Ver qué información expone tu binario.

```bash
./scripts/analyze_ipa.sh /path/a/TuApp.ipa
```

**Validar:**
- [ ] ¿Hay API keys en los strings?
- [ ] ¿Hay endpoints internos expuestos?
- [ ] ¿Los entitlements son los esperados?
- [ ] ¿Hay perfil embebido (no debería en App Store)?

---

## Prueba 2: Re-firma (simula sideloading)

**Objetivo:** Verificar que tu app detecta cuando es re-firmada.

```bash
./scripts/resign_ipa.sh /path/a/TuApp.ipa --cert "Apple Development: tu@email.com"
```

**Instalar y probar:**
```bash
ideviceinstaller -i TuApp_resigned.ipa
```

**Validar que tu app detecta:**
- [ ] Team ID incorrecto (Detección 1)
- [ ] Perfil embebido presente (Detección 5)
- [ ] Entitlements de desarrollo (Detección 4)

**Resultado esperado:** La app debería reportar risk score ≥ 30.

---

## Prueba 3: Inyección de dylib (simula hooking)

**Objetivo:** Verificar que tu app detecta código inyectado.

```bash
./scripts/inject_dylib.sh /path/a/TuApp.ipa --dylib test-dylibs/hook_license.dylib
```

**Instalar y probar:**
```bash
ideviceinstaller -i TuApp_hooked.ipa
```

**Al abrir la app, verificar en Console.app:**
- [ ] ¿Ves el mensaje `[CuySideStore] DYLIB INYECTADA CARGADA`?
- [ ] Si SÍ → tu app NO detectó la inyección ❌
- [ ] Si NO → tu app bloqueó la carga ✓

**Validar que tu app detecta:**
- [ ] Imágenes sospechosas cargadas (Detección 6)
- [ ] Variables de entorno de inyección (Detección 7)

---

## Prueba 4: Entitlements de desarrollo (simula sideloading)

**Objetivo:** Verificar que tu app detecta entitlements de desarrollo.

```bash
./scripts/modify_entitlements.sh /path/a/TuApp.ipa --preset desarrollo
```

**Instalar y probar:**
```bash
ideviceinstaller -i TuApp_entitlements.ipa
```

**Validar:**
- [ ] `get-task-allow` presente (Detección 4)
- [ ] `beta-reports-active` presente (Detección 4)

---

## Prueba 5: Entitlements de plataforma (simula TrollStore)

**Objetivo:** Verificar que tu app detecta entitlements de TrollStore.

```bash
./scripts/modify_entitlements.sh /path/a/TuApp.ipa --preset plataforma
```

**Nota:** iOS rechazará la instalación normal (por eso TrollStore necesita el bug de CoreTrust). Esta prueba valida la **detección** en el código, no la instalación.

**Validar en código:**
- [ ] `platform-application` presente → detectado
- [ ] `com.apple.private.security.no-container` presente → detectado

---

## Prueba 6: Validación server-side

**Objetivo:** Verificar que el servidor rechaza apps parcheadas.

```bash
# Con el servidor corriendo (npm start):

# 1. Reportar señales de tampering (simula app parcheada)
curl -X POST http://localhost:3000/v1/telemetry/security \
  -H "Content-Type: application/json" \
  -H "x-device-id: test-device-001" \
  -H "x-user-id: user-001" \
  -d '{"riskScore": 80, "signals": {"wrong_team_id": true, "embedded_profile": true}}'

# 2. Intentar acceder a features (debería fallar con riesgo alto)
curl http://localhost:3000/v1/features \
  -H "x-device-id: test-device-001" \
  -H "x-user-id: user-001"
# Esperado: 403 "Dispositivo no autorizado"

# 3. Intentar validar suscripción sin assertion (debería fallar)
curl -X POST http://localhost:3000/v1/subscription/validate \
  -H "Content-Type: application/json" \
  -H "x-device-id: test-device-001" \
  -H "x-user-id: user-001" \
  -d '{"userId": "user-001"}'
# Esperado: 403 "Assertion requerida"
```

**Validar:**
- [ ] Riesgo ≥ 70 → 403 en `/v1/features`
- [ ] Sin assertion → 403 en `/v1/subscription/validate`
- [ ] Incidentes registrados en `/v1/debug/incidents/user-001`

---

## Prueba 7: Flujo completo de App Attest

```bash
# 1. Obtener challenge
curl http://localhost:3000/v1/attestation/challenge \
  -H "x-device-id: test-device-001" \
  -H "x-user-id: user-001"

# 2. Verificar attestation (simulado)
curl -X POST http://localhost:3000/v1/attestation/verify \
  -H "Content-Type: application/json" \
  -H "x-device-id: test-device-001" \
  -H "x-user-id: user-001" \
  -d '{"attestation": "fake_attestation_data_12345", "keyId": "fake_key_id_67890"}'

# 3. Ahora validar suscripción con assertion
curl -X POST http://localhost:3000/v1/subscription/validate \
  -H "Content-Type: application/json" \
  -H "x-device-id: test-device-001" \
  -H "x-user-id: user-001" \
  -H "x-app-assertion: fake_assertion_data" \
  -H "x-app-key-id: fake_key_id_67890" \
  -d '{"userId": "user-001"}'
# Esperado: 200 con isValid: true
```

---

## Matriz de resultados esperados

| Prueba | Detección esperada | Risk score esperado |
|---|---|---|
| App original (App Store) | Ninguna | 0 |
| Re-firmada (resign_ipa.sh) | Team ID, perfil embebido, entitlements dev | ≥ 55 |
| Con dylib inyectada | Imágenes sospechosas | ≥ 25 |
| Entitlements desarrollo | get-task-allow, beta-reports | ≥ 15 |
| Entitlements plataforma | platform-application (si se logra instalar) | ≥ 30 |

---

## Solución de problemas

### `ideviceinstaller` no detecta el dispositivo
```bash
# Verificar conexión USB
idevice_id -l
# Si está vacío: probar otro cable/puerto, confiar en la computadora
```

### Error al re-firmar: "no identity found"
```bash
# Ver certificados disponibles
security find-identity -v -p codesigning
# Usar el nombre EXACTO que aparece entre comillas
```

### La dylib no se carga al instalar
```bash
# Verificar que la dylib está firmada
ldid -S test-dylibs/hook_license.dylib
# Verificar el Load Command del binario
otool -L TuApp.app/TuApp | grep hook_license
```

### El servidor no responde
```bash
# Verificar que está corriendo
curl http://localhost:3000/health
# Reiniciar si es necesario
cd server && npm start
```