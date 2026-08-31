#!/bin/bash
#
# CuySideStore — Re-firma de IPA
#
# Re-firma un IPA con un certificado diferente al original.
# Simula exactamente lo que hacen Sideloadly/AltStore/SideStore:
# tu app termina firmada por otro certificado (Team ID diferente).
#
# Uso: ./resign_ipa.sh <archivo.ipa> --cert <nombre_cert> [--output <out.ipa>] [--entitlements <file.plist>]

set -e

# ─── Parsear argumentos ───────────────────────────────────────
IPA_PATH=""
CERT_NAME=""
OUTPUT_PATH=""
ENTITLEMENTS_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --cert)          CERT_NAME="$2"; shift 2 ;;
        --output)        OUTPUT_PATH="$2"; shift 2 ;;
        --entitlements)  ENTITLEMENTS_FILE="$2"; shift 2 ;;
        -*)              echo "Opción desconocida: $1"; exit 1 ;;
        *)               IPA_PATH="$1"; shift ;;
    esac
done

if [ -z "$IPA_PATH" ] || [ -z "$CERT_NAME" ]; then
    echo "Uso: $0 <archivo.ipa> --cert <nombre_cert> [--output <out.ipa>] [--entitlements <file.plist>]"
    echo ""
    echo "Ejemplos:"
    echo "  $0 TuApp.ipa --cert \"Apple Development: oswaldo@ejemplo.com\""
    echo "  $0 TuApp.ipa --cert CuyTestCert --output TuApp_resigned.ipa"
    exit 1
fi

if [ ! -f "$IPA_PATH" ]; then
    echo "❌ ERROR: No existe $IPA_PATH"
    exit 1
fi

# Output por defecto
if [ -z "$OUTPUT_PATH" ]; then
    BASENAME=$(basename "$IPA_PATH" .ipa)
    OUTPUT_PATH="${BASENAME}_resigned.ipa"
fi

WORK_DIR=$(mktemp -d)
PAYLOAD_DIR="$WORK_DIR/Payload"

echo "═════════════════════════════════════════════════════════════"
echo "  CuySideStore — Re-firma de IPA"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "  IPA original:  $IPA_PATH"
echo "  Certificado:   $CERT_NAME"
echo "  Output:        $OUTPUT_PATH"
echo ""

# 1. Verificar que el certificado existe
echo "▸ Verificando certificado..."
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "❌ ERROR: Certificado '$CERT_NAME' no encontrado."
    echo ""
    echo "Certificados disponibles:"
    security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /'
    exit 1
fi
echo "  ✓ Certificado encontrado"

# 2. Extraer el IPA
echo "▸ Extrayendo IPA..."
unzip -q "$IPA_PATH" -d "$WORK_DIR"

if [ ! -d "$PAYLOAD_DIR" ]; then
    echo "❌ ERROR: El IPA no contiene Payload/"
    rm -rf "$WORK_DIR"
    exit 1
fi

# 3. Guardar firma original para comparar
echo "▸ Guardando firma original (para comparación)..."
for app in "$PAYLOAD_DIR"/*.app; do
    APP_NAME=$(basename "$app")
    echo ""
    echo "─── Firma original de $APP_NAME ───"
    codesign -dvvv "$app" 2>&1 | grep -E "Authority|TeamIdentifier" | sed 's/^/  /'
done

# 4. Re-firmar cada app en el Payload
for app in "$PAYLOAD_DIR"/*.app; do
    APP_NAME=$(basename "$app")
    echo ""
    echo "▸ Re-firmando $APP_NAME..."

    # 4a. Preparar entitlements
    SIGN_ARGS=()
    if [ -n "$ENTITLEMENTS_FILE" ]; then
        if [ -f "$ENTITLEMENTS_FILE" ]; then
            echo "  Usando entitlements de: $ENTITLEMENTS_FILE"
            SIGN_ARGS+=(--entitlements)
            SIGN_ARGS+=("$ENTITLEMENTS_FILE")
        else
            echo "  ⚠️ Archivo de entitlements no encontrado: $ENTITLEMENTS_FILE"
            echo "     Firmando SIN entitlements personalizados"
        fi
    else
        # Extraer entitlements originales y reutilizarlos
        # (así la app funciona igual, pero firmada por otro certificado)
        # NOTA: || true evita que set -e mate el script si el binario
        # original no tiene firma/entitlements
        ORIG_ENTITLEMENTS=$(codesign -d --entitlements :- "$app" 2>/dev/null || true)
        if [ -n "$ORIG_ENTITLEMENTS" ]; then
            ENT_FILE="$WORK_DIR/orig_entitlements.plist"
            echo "$ORIG_ENTITLEMENTS" > "$ENT_FILE"
            SIGN_ARGS+=(--entitlements)
            SIGN_ARGS+=("$ENT_FILE")
            echo "  Reutilizando entitlements originales"
        fi
    fi

    # 4b. Re-firmar el binario principal
    # NOTA: no usar if con set -e — capturar exit code explícitamente
    codesign -f -s "$CERT_NAME" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$app" 2>&1
    SIGN_STATUS=$?
    if [ $SIGN_STATUS -eq 0 ]; then
        echo "  ✓ Binario principal re-firmado"
    else
        echo "  ❌ ERROR al re-firmar $APP_NAME (exit $SIGN_STATUS)"
        rm -rf "$WORK_DIR"
        exit 1
    fi

    # 4c. Re-firmar frameworks embebidos (de adentro hacia afuera)
    if [ -d "$app/Frameworks" ]; then
        echo "  ▸ Re-firmando frameworks embebidos..."
        for framework in "$app/Frameworks"/*; do
            if [ -d "$framework" ]; then
                codesign -f -s "$CERT_NAME" "$framework" 2>/dev/null && \
                    echo "    ✓ $(basename "$framework")" || \
                    echo "    ⚠️ Falló: $(basename "$framework")"
            fi
        done
        # Re-firmar el .app de nuevo después de los frameworks
        codesign -f -s "$CERT_NAME" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$app" 2>/dev/null || true
    fi

    # 4d. Verificar la nueva firma
    echo ""
    echo "─── Nueva firma de $APP_NAME ───"
    codesign -dvvv "$app" 2>&1 | grep -E "Authority|TeamIdentifier" | sed 's/^/  /'
done

# 5. Empaquetar el nuevo IPA
echo ""
echo "▸ Empaquetando IPA re-firmado..."
cd "$WORK_DIR"
# Soportar rutas absolutas y relativas para el output
case "$OUTPUT_PATH" in
    /*) ZIP_TARGET="$OUTPUT_PATH" ;;
    *)  ZIP_TARGET="$OLDPWD/$OUTPUT_PATH" ;;
esac
mkdir -p "$(dirname "$ZIP_TARGET")"
zip -qry "$ZIP_TARGET" Payload

# 6. Verificar el IPA final
echo "▸ Verificando IPA final..."
codesign --verify --deep "$PAYLOAD_DIR"/*.app 2>&1 && \
    echo "  ✓ Firma válida en el IPA final" || \
    echo "  ⚠️ Verificación de firma falló (normal si faltan entitlements)"

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  ✓ IPA re-firmado: $OUTPUT_PATH"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "  PRÓXIMOS PASOS:"
echo "  1. Instala en dispositivo:  ideviceinstaller -i $OUTPUT_PATH"
echo "     (o via Xcode → Devices → instalar manualmente)"
echo "  2. Abre tu app y verifica si detecta la re-firma"
echo "  3. Registra resultados en docs/RESULTS-TEMPLATE.md"
echo ""

rm -rf "$WORK_DIR"