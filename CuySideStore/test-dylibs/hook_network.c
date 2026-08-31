//
//  hook_network.c
//  CuySideStore — Dylib de prueba para inyección
//
//  Simula intercepción de red. NO intercepta nada realmente —
//  solo imprime en consola cuando se carga, para verificar si
//  tu app detecta la imagen cargada.
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
static void hook_network_init(void) {
    fprintf(stderr, "\n");
    fprintf(stderr, "╔══════════════════════════════════════════════════════╗\n");
    fprintf(stderr, "║  [CuySideStore] DYLIB DE RED INYECTADA             ║\n");
    fprintf(stderr, "║                                                      ║\n");
    fprintf(stderr, "║  Si ves este mensaje, tu app NO detectó la           ║\n");
    fprintf(stderr, "║  inyección de código antes de hacer peticiones.      ║\n");
    fprintf(stderr, "║                                                      ║\n");
    fprintf(stderr, "║  Un atacante real podría:                            ║\n");
    fprintf(stderr, "║  - Interceptar tráfico HTTPS (bypass de pinning)    ║\n");
    fprintf(stderr, "║  - Robar tokens de sesión                            ║\n");
    fprintf(stderr, "║  - Modificar respuestas del servidor                 ║\n");
    fprintf(stderr, "╚══════════════════════════════════════════════════════╝\n");
    fprintf(stderr, "\n");

    // Verificar variables de entorno de inyección
    // (tu app debería detectar estas también)
    const char *injection_vars[] = {
        "DYLD_INSERT_LIBRARIES",
        "DYLD_PRINT_LIBRARIES",
        "DYLD_PRINT_APIS",
        NULL
    };

    fprintf(stderr, "[CuySideStore] Variables de entorno de inyección:\n");
    for (int i = 0; injection_vars[i] != NULL; i++) {
        const char *value = getenv(injection_vars[i]);
        if (value != NULL) {
            fprintf(stderr, "[CuySideStore]   ⚠️ %s = %s\n", injection_vars[i], value);
        }
    }

    // Listar imágenes cargadas
    uint32_t count = _dyld_image_count();
    fprintf(stderr, "[CuySideStore] Total de imágenes cargadas: %u\n", count);
    fprintf(stderr, "\n");
}