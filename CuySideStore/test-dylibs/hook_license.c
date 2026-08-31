//
//  hook_license.c
//  CuySideStore — Dylib de prueba para inyección
//
//  Simula un bypass de licencia. NO hace bypass real — solo
//  imprime en consola cuando se carga, para que puedas verificar
//  si tu app detecta la imagen cargada.
//
//  ⚠️ SOLO PARA PRUEBAS DE SEGURIDAD EN TUS PROPIAS APPS
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

// Constructor — se ejecuta cuando la dylib se carga
__attribute__((constructor))
static void hook_license_init(void) {
    fprintf(stderr, "\n");
    fprintf(stderr, "╔══════════════════════════════════════════════════════╗\n");
    fprintf(stderr, "║  [CuySideStore] DYLIB INYECTADA CARGADA             ║\n");
    fprintf(stderr, "║                                                      ║\n");
    fprintf(stderr, "║  Si ves este mensaje en los logs de tu app,          ║\n");
    fprintf(stderr, "║  tu app NO detectó la inyección de código.          ║\n");
    fprintf(stderr, "║                                                      ║\n");
    fprintf(stderr, "║  Detecciones que deberían haberla capturado:         ║\n");
    fprintf(stderr, "║  - _dyld_image_count() / _dyld_get_image_name()      ║\n");
    fprintf(stderr, "║  - Verificación de Load Commands                     ║\n");
    fprintf(stderr, "║  - Detección de dylibs desconocidas                  ║\n");
    fprintf(stderr, "╚══════════════════════════════════════════════════════╝\n");
    fprintf(stderr, "\n");

    // Listar todas las imágenes cargadas (lo que tu app debería hacer)
    uint32_t count = _dyld_image_count();
    fprintf(stderr, "[CuySideStore] Imágenes cargadas en el proceso: %u\n", count);
    fprintf(stderr, "[CuySideStore] Esta dylib es una de ellas — tu app debería detectarla.\n");
    fprintf(stderr, "\n");
}