#!/bin/bash
#
# CuySideStore — Inyección de dylib en IPA
#
# Inyecta una dylib de prueba en un IPA modificando el Load Command
# del binario principal. Simula lo que hace Sideloadly con su
# feature "Inject dylibs" — el vector de ataque más directo.
#
# Requiere: ldid (brew install ldid), insert_dylib (ver abajo)
#
# Uso: ./inject_dylib.sh <archivo.ipa> --dylib <ruta.dylib> [--output <out.ipa>]

set -e

# ─── Parsear argumentos ───────────────────────────────────────
IPA_PATH=""
DYLIB_PATH=""
OUTPUT_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dylib)   DYLIB_PATH="$2"; shift 2 ;;
        --output)  OUTPUT_PATH="$2"; shift 2 ;;
        -*)        echo "Opción desconocida: $1"; exit 1 ;;
        *)         IPA_PATH="$1"; shift ;;
    esac
done

if [ -z "$IPA_PATH" ] || [ -z "$DYLIB_PATH" ]; then
    echo "Uso: $0 <archivo.ipa> --dylib <ruta.dylib> [--output <out.ipa>]"
    echo ""
    echo "Ejemplo:"
    echo "  $0 TuApp.ipa --dylib test-dylibs/hook_license.dylib --output TuApp_hooked.ipa"
    exit 1
fi

if [ ! -f "$IPA_PATH" ]; then
    echo "❌ ERROR: No existe $IPA_PATH"
    exit 1
fi

if [ ! -f "$DYLIB_PATH" ]; then
    echo "❌ ERROR: No existe $DYLIB_PATH"
    echo ""
    echo "Compila las dylibs de prueba primero:"
    echo "  cd test-dylibs && make"
    exit 1
fi

# Output por defecto
if [ -z "$OUTPUT_PATH" ]; then
    BASENAME=$(basename "$IPA_PATH" .ipa)
    OUTPUT_PATH="${BASENAME}_hooked.ipa"
fi

# Verificar insert_dylib
INSERT_DYLIB="insert_dylib"
if ! command -v insert_dylib &>/dev/null; then
    echo "❌ ERROR: insert_dylib no está instalado."
    echo ""
    echo "Instálalo con:"
    echo "  brew install insert_dylib"
    echo ""
    echo "O compílalo desde fuente:"
    echo "  git clone https://github.com/Tyilo/insert_dylib"
    echo "  cd insert_dylib"
    echo "  xcodebuild -project insert_dylib.xcodeproj"
    echo "  cp build/Release/insert_dylib /usr/local/bin/"
    exit 1
fi

WORK_DIR=$(mktemp -d)
PAYLOAD_DIR="$WORK_DIR/Payload"

echo "═════════════════════════════════════════════════════════════"
echo "  CuySideStore — Inyección de dylib en IPA"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "  IPA original:  $IPA_PATH"
echo "  Dylib:         $DYLIB_PATH"
echo "  Output:        $OUTPUT_PATH"
echo ""

# 1. Extraer el IPA
echo "▸ Extrayendo IPA..."
unzip -q "$IPA_PATH" -d "$WORK_DIR"

if [ ! -d "$PAYLOAD_DIR" ]; then
    echo "❌ ERROR: El IPA no contiene Payload/"
    rm -rf "$WORK_DIR"
    exit 1
fi

# 2. Procesar cada app
for app in "$PAYLOAD_DIR"/*.app; do
    APP_NAME=$(basename "$app")
    BUNDLE_EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist" 2>/dev/null)
    BINARY="$app/$BUNDLE_EXECUTABLE"

    echo ""
    echo "▸ Procesando $APP_NAME..."

    # 2a. Copiar la dylib dentro del .app
    DYLIB_NAME=$(basename "$DYLIB_PATH")
    cp "$DYLIB_PATH" "$app/$DYLIB_NAME"
    echo "  ✓ Dylib copiada: $app/$DYLIB_NAME"

    # 2b. Modificar el Load Command del binario principal
    #     Esto hace que iOS cargue la dylib al iniciar la app
    echo "  ▸ Modificando Load Commands del binario..."
    if "$INSERT_DYLIB" --inplace --weak "$DYLIB_NAME" "$BINARY" 2>&1; then
        echo "  ✓ Load Command agregado: @executable_path/$DYLIB_NAME"
    else
        echo "  ❌ ERROR al modificar el binario"
        rm -rf "$WORK_DIR"
        exit 1
    fi

    # 2c. Firmar la dylib (necesario para que iOS la cargue)
    echo "  ▸ Firmando la dylib..."
    if command -v ldid &>/dev/null; then
        ldid -S "$app/$DYLIB_NAME" && echo "  ✓ Dylib firmada con ldid"
    else
        echo "  ⚠️ ldid no disponible — la dylib podría no cargarse"
        echo "     Instálalo: brew install ldid"
    fi

    # 2d. Re-firmar el binario modificado
    #     Usamos el certificado de desarrollo disponible
    echo "  ▸ Re-firmando binario modificado..."
    CERT=$(security find-identity -v -p codesigning 2>/dev/null | \
        grep "Apple Development" | head -1 | \
        sed 's/.*"\(.*\)".*/\1/')
    
    if [ -n "$CERT" ]; then
        # Extraer entitlements originales
        ORIG_ENTITLEMENTS=$(codesign -d --entitlements :- "$app" 2>/dev/null)
        ENT_ARGS=()
        if [ -n "$ORIG_ENTITLEMENTS" ]; then
            ENT_FILE="$WORK_DIR/ent.plist"
            echo "$ORIG_ENTITLEMENTS" > "$ENT_FILE"
            ENT_ARGS+=(--entitlements "$ENT_FILE")
        fi
        codesign -f -s "$CERT" "${ENT_ARGS[@]}" "$app" && \
            echo "  ✓ Re-firmado con: $CERT"
    else
        echo "  ⚠️ Sin certificado de desarrollo — usando ldid"
        ldid -S "$BINARY"
    fi
done

# 3. Empaquetar el nuevo IPA
echo ""
echo "▸ Empaquetando IPA con dylib inyectada..."
cd "$WORK_DIR"
zip -qry "$OLDPWD/$OUTPUT_PATH" Payload

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  ✓ IPA con dylib inyectada: $OUTPUT_PATH"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "  LA DYLIB SE CARGARÁ AL INICIAR LA APP."
echo "  Verifica si tu app detecta la imagen cargada:"
echo "  - _dyld_image_count() / _dyld_get_image_name()"
echo "  - Detección de DYLD_INSERT_LIBRARIES"
echo ""
echo "  PRÓXIMOS PASOS:"
echo "  1. Instala: ideviceinstaller -i $OUTPUT_PATH"
echo "  2. Abre tu app — la dylib imprime en consola al cargarse"
echo "  3. Verifica los logs: Console.app → tu dispositivo → tu app"
echo ""

rm -rf "$WORK_DIR"