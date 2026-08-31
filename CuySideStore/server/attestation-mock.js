//
//  attestation-mock.js
//  CuySideStore — Mock de App Attest
//
//  Simula las respuestas del servidor de Apple para App Attest,
//  para que puedas probar el flujo completo de tu app sin
//  necesitar la clave .p8 real de DeviceCheck.
//
//  ⚠️ SOLO PARA DESARROLLO/PRUEBAS — en producción usa la API real
//

const crypto = require('crypto');

// Almacén en memoria de claves registradas por dispositivo
// (en producción: base de datos)
const registeredKeys = new Map();

// Almacén de challenges pendientes
const pendingChallenges = new Map();

class AttestationMock {

    /**
     * Genera un challenge único para el flujo de attestation.
     * Equivalente al endpoint de tu servidor que genera el challenge.
     */
    static generateChallenge(deviceId) {
        const challenge = crypto.randomBytes(32).toString('hex');
        pendingChallenges.set(deviceId, {
            challenge,
            createdAt: Date.now(),
            expiresAt: Date.now() + (5 * 60 * 1000) // 5 minutos
        });
        return challenge;
    }

    /**
     * Valida un attestation (simula la llamada a Apple).
     *
     * En producción, esto se hace con:
     * POST https://developer.apple.com/devicecheck/validateattestation
     *
     * Aquí simulamos la respuesta para poder probar el flujo.
     */
    static validateAttestation(deviceId, attestation, keyId) {
        const pending = pendingChallenges.get(deviceId);

        if (!pending) {
            return { success: false, error: 'No hay challenge pendiente' };
        }

        if (Date.now() > pending.expiresAt) {
            pendingChallenges.delete(deviceId);
            return { success: false, error: 'Challenge expirado' };
        }

        // Simular verificación con Apple
        // En producción: enviar a Apple y verificar la respuesta
        const isValidFormat = attestation && attestation.length > 10 && keyId && keyId.length > 5;

        if (!isValidFormat) {
            return { success: false, error: 'Attestation inválida' };
        }

        // Simular clave pública del dispositivo
        const publicKey = crypto.createHash('sha256')
            .update(keyId + deviceId)
            .digest('base64');

        // Registrar la clave
        registeredKeys.set(deviceId, {
            keyId,
            publicKey,
            registeredAt: Date.now()
        });

        // Limpiar el challenge usado
        pendingChallenges.delete(deviceId);

        return {
            success: true,
            publicKey
        };
    }

    /**
     * Valida una assertion para una petición crítica.
     *
     * En producción, esto se hace con:
     * POST https://developer.apple.com/devicecheck/validateassertion
     */
    static validateAssertion(deviceId, assertion, keyId, requestData) {
        const registered = registeredKeys.get(deviceId);

        if (!registered) {
            return { success: false, error: 'Dispositivo no registrado' };
        }

        if (registered.keyId !== keyId) {
            return { success: false, error: 'Key ID no coincide' };
        }

        // Simular verificación de la assertion
        // En producción: verificar la firma criptográfica con Apple
        const expectedHash = crypto.createHash('sha256')
            .update(requestData)
            .digest('hex');

        const isValid = assertion && assertion.length > 10;

        if (!isValid) {
            return { success: false, error: 'Assertion inválida' };
        }

        return { success: true };
    }

    /**
     * Verifica si un dispositivo está registrado (attestation completado).
     */
    static isDeviceRegistered(deviceId) {
        return registeredKeys.has(deviceId);
    }

    /**
     * Para pruebas: limpiar todos los registros.
     */
    static reset() {
        registeredKeys.clear();
        pendingChallenges.clear();
    }
}

module.exports = AttestationMock;