# CuySideStore — Makefile para dylibs de prueba
#
# Compila las dylibs de prueba para inyección en IPAs.
#
# Uso:
#   make            — Compila todas las dylibs
#   make clean      — Limpia los binarios compilados
#
# Requisitos: Xcode Command Line Tools (clang para iOS)

CC = clang
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
ARCHS = arm64

# Flags para compilar para iOS (dispositivo físico)
CFLAGS = -arch $(ARCHS) \
         -isysroot $(SDK) \
         -miphoneos-version-min=14.0 \
         -dynamiclib \
         -O2 \
         -Wall

# Dylibs a compilar
DYLIBS = hook_license.dylib hook_network.dylib

all: $(DYLIBS)

hook_license.dylib: hook_license.c
	$(CC) $(CFLAGS) -o $@ $<
	@echo "✓ Compilada: $@"

hook_network.dylib: hook_network.c
	$(CC) $(CFLAGS) -o $@ $<
	@echo "✓ Compilada: $@"

# Firmar las dylibs con ldid (necesario para que iOS las cargue)
sign: $(DYLIBS)
	@for dylib in $(DYLIBS); do \
		if command -v ldid >/dev/null 2>&1; then \
			ldid -S $$dylib && echo "✓ Firmada: $$dylib"; \
		else \
			echo "⚠️ ldid no instalado — firma con codesign manualmente"; \
		fi \
	done

clean:
	rm -f $(DYLIBS)
	@echo "✓ Limpieza completada"

.PHONY: all clean sign