#!/bin/bash
#
# CuySideStore — Análisis estático de IPA
#
# Extrae y analiza un IPA para pruebas de seguridad:
#   1. Estructura del IPA
#   2. Entitlements originales
#   3. Strings sospechosos (API keys, endpoints)
#   4. Símbolos y clases expuestas
#
# Uso: ./analyze_ipa.sh <archivo.ipa>

set -e

if [ $# -ne 1 ]; then
    echo "Uso: $0 <archivo.ipa>"
    exit 1
fi

IPA_PATH="$1"
WORK_DIR=$(mktemp -d)
PAYLOAD_DIR="$WORK_DIR/Payload"

echo "═════════════════════════════════════════════════════════════"
echo "  CuySideStore — Análisis estático de IPA"
echo "═════════════════════════════════════════════════════════════"
echo ""

# 1. Extraer el IPA
echo "▸ Extrayendo IPA..."
unzip -q "$IPA_PATH" -d "$WORK_DIR"

if [ ! -d "$PAYLOAD_DIR" ]; then
    echo "❌ ERROR: El IPA no contiene un directorio Payload/"
    rm -rf "$WORK_DIR"
    exit 1
fi

# 2. Listar apps en el Payload
echo ""
echo "─── Apps en el IPA ───"
for app in "$PAYLOAD_DIR"/*.app; do
    APP_NAME=$(basename "$app")
    echo "  • $APP_NAME"
done

# 3. Analizar cada app
for app in "$PAYLOAD_DIR"/*.app; do
    APP_NAME=$(basename "$app")
    BUNDLE_EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist" 2>/dev/null)
    BINARY="$app/$BUNDLE_EXECUTABLE"

    echo ""
    echo "═════════════════════════════════════════════════════════════"
    echo "  Análisis de: $APP_NAME"
    echo "═════════════════════════════════════════════════════════════"

    # Info.plist básico
    echo ""
    echo "─── Información básica ───"
    echo "  Bundle ID:      $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist" 2>/dev/null)"
    echo "  Versión:        $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist" 2>/dev/null)"
    echo "  Executable:     $BUNDLE_EXECUTABLE"
    echo "  Min iOS:        $(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist" 2>/dev/null)"

    # Verificar firma
    echo ""
    echo "─── Firma del binario ───"
    if codesign -dvvv "$app" 2>&1 | grep -q "Authority"; then
        codesign -dvvv "$app" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier=" | sed 's/^/  /'
    else
        echo "  ⚠️ Sin firma o firma ilegible"
    fi

    # Entitlements
    echo ""
    echo "─── Entitlements ───"
    ENTITLEMENTS=$(codesign -d --entitlements :- "$app" 2>/dev/null)
    if [ -n "$ENTITLEMENTS" ]; then
        echo "$ENTITLEMENTS" | grep -E "^\s+<key>" | sed 's/<[^>]*>//g' | sed 's/^ *//' | sed 's/^/  /'
    else
        echo "  (sin entitlements)"
    fi

    # Perfil embebido
    echo ""
    echo "─── Perfil de aprovisionamiento ───"
    if [ -f "$app/embedded.mobileprovision" ]; then
        echo "  ⚠️ PRESENTE — apps del App Store NO deberían tenerlo"
        echo "     (presente = instalada via sideloading o desarrollo)"
        TEAM_ID=$(security cms -D -i "$app/embedded.mobileprovision" 2>/dev/null | \
            /usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' /dev/stdin 2>/dev/null)
        echo "  Team ID del perfil: $TEAM_ID"
    else
        echo "  ✓ Ausente (normal para App Store)"
    fi

    # Strings sospechosos
    echo ""
    echo "─── Strings de seguridad (posibles secretos) ───"
    if [ -f "$BINARY" ]; then
        SUSPICIOUS=$(strings "$BINARY" | grep -iE "api[_-]?key|secret|token|password|credential|private[_-]?key" | head -20)
        if [ -n "$SUSPICIOUS" ]; then
            echo "$SUSPICIOUS" | sed 's/^/  ⚠️ /'
        else
            echo "  ✓ No se encontraron strings obvios de secretos"
        fi

        # Endpoints
        echo ""
        echo "─── Endpoints de red ───"
        strings "$BINARY" | grep -oE "https?://[a-zA-Z0-9./_-]+" | sort -u | head -20 | sed 's/^/  /'
    fi

    # Frameworks embebidos
    echo ""
    echo "─── Frameworks embebidos ───"
    if [ -d "$app/Frameworks" ]; then
        ls "$app/Frameworks" | sed 's/^/  /'
    else
        echo "  (ninguno)"
    fi
done

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  Análisis completado."
echo "═════════════════════════════════════════════════════════════"

rm -rf "$WORK_DIR"