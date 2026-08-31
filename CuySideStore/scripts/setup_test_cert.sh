#!/bin/bash
#
# CuySideStore — Configuración de certificado de pruebas
#
# Crea un certificado autofirmado en el Keychain de macOS para
# re-firmar IPAs en pruebas de seguridad. Simula lo que hacen
# Sideloadly/AltStore/SideStore con el Apple ID del usuario.
#
# Uso: ./setup_test_cert.sh

set -e

CERT_NAME="CuyTestCert"
KEYCHAIN="login.keychain-db"

echo "═════════════════════════════════════════════════════════════"
echo "  CuySideStore — Configuración de certificado de pruebas"
echo "═════════════════════════════════════════════════════════════"
echo ""

# 1. Verificar si ya existe
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ El certificado '$CERT_NAME' ya existe en el keychain."
    echo "  Si quieres recrearlo, elimínalo primero:"
    echo "    security delete-identity -c $CERT_NAME"
    exit 0
fi

echo "▸ Creando certificado autofirmado '$CERT_NAME'..."

# 2. Crear el certificado usando el asistente de Keychain Access
#    (Apple no permite crear certificados de codesigning via CLI puro,
#     pero podemos usar el método del certificado de desarrollo)
echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  INSTRUCCIONES MANUALES (una sola vez)"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "Apple no permite crear certificados de codesigning completamente"
echo "via CLI. Necesitas crearlo una vez manualmente:"
echo ""
echo "  1. Abre 'Keychain Access' (Acceso a Llaveros)"
echo "  2. Menú: Keychain Access → Certificate Assistant →"
echo "     Create Certificate..."
echo "  3. Configura:"
echo "     - Name: $CERT_NAME"
echo "     - Identity Type: Self Signed Root"
echo "     - Certificate Type: Code Signing"
echo "     - ✅ Marca 'Let me override defaults'"
echo "  4. En 'Serial Number': usa un valor único"
echo "  5. En 'Validity': 3650 días (10 años)"
echo "  6. Continúa hasta 'Key Usage' → ✅ Signature"
echo "  7. En 'Extended Key Usage' → ✅ Code Signing"
echo "  8. Guarda en 'login' keychain"
echo ""
echo "  ALTERNATIVA (más rápida): usa tu certificado de desarrollo"
echo "  de Apple (Apple Development) que ya tienes en el keychain"
echo "  por tener Xcode instalado:"
echo ""
echo "    security find-identity -v -p codesigning"
echo ""
echo "  Cualquier certificado 'Apple Development' funciona para las"
echo "  pruebas — es exactamente lo que usa Sideloadly."
echo ""

# 3. Listar certificados disponibles
echo "─── Certificados de codesigning disponibles ───"
security find-identity -v -p codesigning 2>/dev/null | head -10 | sed 's/^/  /'

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  Cuando tengas el certificado, úsalo en resign_ipa.sh:"
echo "    ./resign_ipa.sh app.ipa --cert \"$CERT_NAME\" --output out.ipa"
echo "═════════════════════════════════════════════════════════════"