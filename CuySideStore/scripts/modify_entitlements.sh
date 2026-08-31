#!/bin/bash
#
# CuySideStore — Modificación de entitlements de un IPA
#
# Reemplaza los entitlements de un IPA con un set personalizado.
# Simula lo que hace TrollStore (entitlements de plataforma) y
# lo que permite Sideloadly (entitlements personalizados).
#
# Uso: ./modify_entitlements.sh <archivo.ipa> [--preset <plataforma|desarrollo|custom>] [--file <ent.plist>] [--output <out.ipa>]

set -e

# ─── Parsear argumentos ───────────────────────────────────────
IPA_PATH=""
PRESET=""
ENT_FILE=""
OUTPUT_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --preset)  PRESET="$2"; shift 2 ;;
        --file)    ENT_FILE="$2"; shift 2 ;;
        --output)  OUTPUT_PATH="$2"; shift 2 ;;
        -*)        echo "Opción desconocida: $1"; exit 1 ;;
        *)         IPA_PATH="$1"; shift ;;
    esac
done

if [ -z "$IPA_PATH" ]; then
    echo "Uso: $0 <archivo.ipa> [--preset <plataforma|desarrollo|custom>] [--file <ent.plist>] [--output <out.ipa>]"
    echo ""
    echo "Presets disponibles:"
    echo "  plataforma  — Simula TrollStore: entitlements de plataforma"
    echo "                (no-container, AppDataContainers, platform-application)"
    echo "  desarrollo  — Simula sideloading: entitlements de desarrollo"
    echo "                (get-task-allow, beta-reports-active)"
    echo "  custom      — Usa el archivo especificado con --file"
    exit 1
fi

if [ ! -f "$IPA_PATH" ]; then
    echo "❌ ERROR: No existe $IPA_PATH"
    exit 1
fi

# Output por defecto
if [ -z "$OUTPUT_PATH" ]; then
    BASENAME=$(basename "$IPA_PATH" .ipa)
    OUTPUT_PATH="${BASENAME}_entitlements.ipa"
fi

WORK_DIR=$(mktemp -d)
PAYLOAD_DIR="$WORK_DIR/Payload"
ENT_DIR="$WORK_DIR/entitlements"
mkdir -p "$ENT_DIR"

echo "═════════════════════════════════════════════════════════════"
echo "  CuySideStore — Modificación de entitlements"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "  IPA original:  $IPA_PATH"
echo "  Preset:         ${PRESET:-custom}"
echo "  Output:         $OUTPUT_PATH"
echo ""

# 1. Generar el archivo de entitlements según el preset
echo "▸ Generando entitlements..."

case "$PRESET" in
    plataforma)
        # Simula lo que hace TrollStore — entitlements de plataforma
        cat > "$ENT_DIR/new_entitlements.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.private.security.no-container</key>
    <true/>
    <key>com.apple.private.security.storage.AppDataContainers</key>
    <true/>
    <key>platform-application</key>
    <true/>
    <key>com.apple.private.security.no-sandbox</key>
    <true/>
    <key>application-identifier</key>
    <string>$(AppIdentifierPrefix)com.cuycoders.testapp</string>
    <key>com.apple.developer.team-identifier</key>
    <string>CUYTESTTEAM</string>
</dict>
</plist>
EOF
        echo "  ✓ Preset 'plataforma' (simula TrollStore)"
        ;;
    desarrollo)
        # Simula sideloading con Apple ID — entitlements de desarrollo
        cat > "$ENT_DIR/new_entitlements.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>get-task-allow</key>
    <true/>
    <key>beta-reports-active</key>
    <true/>
    <key>com.apple.developer.team-identifier</key>
    <string>PERSONALTEAM123</string>
    <key>application-identifier</key>
    <string>PERSONALTEAM123.com.cuycoders.testapp</string>
</dict>
</plist>
EOF
        echo "  ✓ Preset 'desarrollo' (simula sideloading)"
        ;;
    *)
        # Custom — usar archivo especificado
        if [ -n "$ENT_FILE" ] && [ -f "$ENT_FILE" ]; then
            cp "$ENT_FILE" "$ENT_DIR/new_entitlements.plist"
            echo "  ✓ Usando archivo custom: $ENT_FILE"
        else
            echo "❌ ERROR: Preset '$PRESET' no válido o archivo --file no especificado"
            rm -rf "$WORK_DIR"
            exit 1
        fi
        ;;
esac

# 2. Extraer el IPA
echo "▸ Extrayendo IPA..."
unzip -q "$IPA_PATH" -d "$WORK_DIR"

if [ ! -d "$PAYLOAD_DIR" ]; then
    echo "❌ ERROR: El IPA no contiene Payload/"
    rm -rf "$WORK_DIR"
    exit 1
fi

# 3. Guardar entitlements originales para comparación
echo ""
echo "─── Entitlements ORIGINALES ───"
for app in "$PAYLOAD_DIR"/*.app; do
    codesign -d --entitlements :- "$app" 2>/dev/null | \
        grep -E "^\s+<key>" | sed 's/<[^>]*>//g' | sed 's/^ *//' | sed 's/^/  /'
done

# 4. Re-firmar con los nuevos entitlements
CERT=$(security find-identity -v -p codesigning 2>/dev/null | \
    grep "Apple Development" | head -1 | \
    sed 's/.*"\(.*\)".*/\1/')

if [ -z "$CERT" ]; then
    echo "❌ ERROR: No hay certificado de desarrollo disponible."
    echo "   Abre Xcode una vez para generar uno, o crea uno manualmente."
    rm -rf "$WORK_DIR"
    exit 1
fi

for app in "$PAYLOAD_DIR"/*.app; do
    APP_NAME=$(basename "$app")
    echo ""
    echo "▸ Re-firmando $APP_NAME con nuevos entitlements..."
    codesign -f -s "$CERT" --entitlements "$ENT_DIR/new_entitlements.plist" "$app" && \
        echo "  ✓ Re-firmado con entitlements modificados"
done

# 5. Mostrar los nuevos entitlements
echo ""
echo "─── Entitlements NUEVOS ───"
for app in "$PAYLOAD_DIR"/*.app; do
    codesign -d --entitlements :- "$app" 2>/dev/null | \
        grep -E "^\s+<key>" | sed 's/<[^>]*>//g' | sed 's/^ *//' | sed 's/^/  /'
done

# 6. Empaquetar el nuevo IPA
echo ""
echo "▸ Empaquetando IPA..."
cd "$WORK_DIR"
# Soportar rutas absolutas y relativas para el output
case "$OUTPUT_PATH" in
    /*) ZIP_TARGET="$OUTPUT_PATH" ;;
    *)  ZIP_TARGET="$OLDPWD/$OUTPUT_PATH" ;;
esac
mkdir -p "$(dirname "$ZIP_TARGET")"
zip -qry "$ZIP_TARGET" Payload

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  ✓ IPA con entitlements modificados: $OUTPUT_PATH"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "  NOTA: iOS RECHAZARÁ entitlements de plataforma en instalación"
echo "  normal (por eso TrollStore necesita el bug de CoreTrust)."
echo "  Para probar la DETECCIÓN de entitlements en tu app, usa el"
echo "  preset 'desarrollo' que sí se instala normalmente."
echo ""
echo "  PRÓXIMOS PASOS:"
echo "  1. Instala: ideviceinstaller -i $OUTPUT_PATH"
echo "  2. Verifica si tu app detecta entitlements inesperados"
echo "     (SecTaskCopyValueForEntitlement con platform-application)"
echo ""

rm -rf "$WORK_DIR"