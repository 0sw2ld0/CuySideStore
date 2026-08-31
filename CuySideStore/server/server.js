//
//  server.js
//  CuySideStore — Servidor de pruebas
//
//  API de pruebas para validar que tu servidor rechaza peticiones
//  de apps parcheadas/sideloaded. Implementa:
//    1. Flujo de App Attest (con mock para desarrollo)
//    2. Middleware de verificación de riesgo
//    3. Endpoints protegidos de ejemplo
//
//  ⚠️ SOLO PARA PRUEBAS — en producción usa la API real de Apple
//

const express = require('express');
const AttestationMock = require('./attestation-mock');

const app = express();
app.use(express.json());

// ─── Almacén de riesgo en memoria (en producción: base de datos) ───
const deviceRiskScores = new Map();
const userIncidents = new Map();

// ─── Middleware: autenticación simulada ───────────────────────
// En producción: verificar JWT/session real
function authenticateUser(req, res, next) {
    const deviceId = req.headers['x-device-id'];
    const userId = req.headers['x-user-id'];

    if (!deviceId || !userId) {
        return res.status(401).json({ error: 'Autenticación requerida' });
    }

    req.deviceId = deviceId;
    req.user = { id: userId };
    next();
}

// ─── Middleware: verificación de riesgo ────────────────────────
function checkDeviceRisk(req, res, next) {
    const riskScore = deviceRiskScores.get(req.deviceId) || 0;

    if (riskScore >= 70) {
        return res.status(403).json({
            error: 'Dispositivo no autorizado',
            reason: 'risk_score_too_high',
            riskScore
        });
    }

    if (riskScore >= 30) {
        // Riesgo medio: requerir App Attest
        req.requireAttestation = true;
    }

    next();
}

// ─── Middleware: App Attest para endpoints críticos ────────────
function requireAppAttest(req, res, next) {
    const assertion = req.headers['x-app-assertion'];
    const keyId = req.headers['x-app-key-id'];

    if (!assertion || !keyId) {
        return res.status(403).json({
            error: 'Assertion requerida',
            reason: 'app_not_attested'
        });
    }

    // Reconstruir los datos de la petición (como los firma el cliente)
    const requestData = `${req.originalUrl}${JSON.stringify(req.body)}`;

    const result = AttestationMock.validateAssertion(
        req.deviceId, assertion, keyId, requestData
    );

    if (!result.success) {
        logSecurityIncident(req.user.id, 'assertion_failed', result);
        return res.status(403).json({
            error: 'App no verificada',
            reason: 'assertion_invalid'
        });
    }

    next();
}

// ─── Helper: registrar incidentes de seguridad ─────────────────
function logSecurityIncident(userId, type, details) {
    if (!userIncidents.has(userId)) {
        userIncidents.set(userId, []);
    }
    userIncidents.get(userId).push({
        type,
        details,
        timestamp: new Date().toISOString()
    });
    console.log(`[SECURITY] Incidente: ${type} — usuario: ${userId}`);
}

// ══════════════════════════════════════════════════════════════
//  ENDPOINTS
// ══════════════════════════════════════════════════════════════

// ─── 1. Health check ───────────────────────────────────────────
app.get('/health', (req, res) => {
    res.json({ status: 'ok', time: new Date().toISOString() });
});

// ─── 2. Reporte de estado del dispositivo (telemetría) ─────────
// La app reporta las señales de tampering detectadas
app.post('/v1/telemetry/security', authenticateUser, (req, res) => {
    const { signals, riskScore } = req.body;

    if (typeof riskScore === 'number') {
        deviceRiskScores.set(req.deviceId, riskScore);
    }

    // Analizar señales individuales
    if (signals) {
        const strongSignals = [
            signals.wrong_team_id,
            signals.embedded_profile,
            signals.invalid_signature
        ].filter(Boolean).length;

        if (strongSignals > 0) {
            logSecurityIncident(req.user.id, 'sideload_detected', signals);
        }
    }

    res.json({ ok: true });
});

// ─── 3. App Attest: generar challenge ──────────────────────────
app.get('/v1/attestation/challenge', authenticateUser, (req, res) => {
    const challenge = AttestationMock.generateChallenge(req.deviceId);
    res.json({ challenge });
});

// ─── 4. App Attest: verificar attestation ───────────────────────
app.post('/v1/attestation/verify', authenticateUser, (req, res) => {
    const { attestation, keyId } = req.body;

    if (!attestation || !keyId) {
        return res.status(400).json({ error: 'Faltan datos' });
    }

    const result = AttestationMock.validateAttestation(
        req.deviceId, attestation, keyId
    );

    if (!result.success) {
        logSecurityIncident(req.user.id, 'attestation_failed', result);
        return res.status(403).json(result);
    }

    res.json({ verified: true });
});

// ─── 5. Endpoint protegido: features habilitadas ────────────────
// El servidor decide qué features tiene el usuario — nunca el cliente
app.get('/v1/features', authenticateUser, checkDeviceRisk, (req, res) => {
    // Simular verificación de suscripción
    // En producción: consultar StoreKit / base de datos de suscripciones
    const isSubscribed = req.headers['x-test-subscribed'] === 'true';

    const features = isSubscribed
        ? ['premium_filter', 'no_ads', 'export', 'cloud_sync']
        : ['basic_filter'];

    res.json({ features });
});

// ─── 6. Endpoint protegido con App Attest: datos sensibles ─────
app.post('/v1/subscription/validate',
    authenticateUser,
    checkDeviceRisk,
    requireAppAttest,
    (req, res) => {
        // Solo llega aquí si:
        // 1. El usuario está autenticado
        // 2. El riesgo del dispositivo es < 70
        // 3. La assertion de App Attest es válida

        const { userId } = req.body;

        // Simular verificación con App Store Server API
        const isValid = true; // En producción: verificar con Apple

        res.json({ isValid, source: 'server_verified' });
    });

// ─── 7. Consultar incidentes (para debugging de pruebas) ───────
app.get('/v1/debug/incidents/:userId', (req, res) => {
    const incidents = userIncidents.get(req.params.userId) || [];
    res.json({ incidents });
});

// ─── 8. Reset para pruebas ──────────────────────────────────────
app.post('/v1/debug/reset', (req, res) => {
    AttestationMock.reset();
    deviceRiskScores.clear();
    userIncidents.clear();
    res.json({ ok: true });
});

// ══════════════════════════════════════════════════════════════
//  INICIAR SERVIDOR
// ══════════════════════════════════════════════════════════════

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log('');
    console.log('═════════════════════════════════════════════════════════════');
    console.log('  CuySideStore — Servidor de pruebas');
    console.log('═════════════════════════════════════════════════════════════');
    console.log(`  Escuchando en: http://localhost:${PORT}`);
    console.log('');
    console.log('  Endpoints de prueba:');
    console.log('    GET  /health                        — Health check');
    console.log('    POST /v1/telemetry/security         — Reportar señales de tampering');
    console.log('    GET  /v1/attestation/challenge      — App Attest: challenge');
    console.log('    POST /v1/attestation/verify         — App Attest: verificación');
    console.log('    GET  /v1/features                   — Features (protegido por riesgo)');
    console.log('    POST /v1/subscription/validate     — Suscripción (protegido por App Attest)');
    console.log('    GET  /v1/debug/incidents/:userId     — Ver incidentes');
    console.log('    POST /v1/debug/reset                — Reset para nuevas pruebas');
    console.log('');
    console.log('  ⚠️ MOCK de App Attest activo — para producción usa la API real de Apple');
    console.log('═════════════════════════════════════════════════════════════');
    console.log('');
});