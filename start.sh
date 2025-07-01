#!/bin/sh
# ============================================================================
# Script de arranque para descargar archivos base del stack domótico
# Autor: epulaecorp
# Repositorio: https://github.com/epulaecorp/NAS
#
# 
# chmod +x bootstrap.sh
# ============================================================================
set -e

# --- Configuración ---
REPO_URL="https://raw.githubusercontent.com/epulaecorp/NAS/main"
DEST_DIR="/volume1/docker"
FILES="docker-compose.yml setup.sh update.sh"

# --- Funciones auxiliares ---
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1"; }
success() { printf "\033[1;32m[OK]\033[0m %s\n" "$1"; }
error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2; }

# --- Verificar conexión ---
log "Verificando conexión a internet..."
if ! ping -c 1 github.com >/dev/null 2>&1; then
  error "No hay conexión a internet. Verifica tu red."
  exit 1
fi
success "Conexión verificada."

# --- Crear estructura si no existe ---
log "Creando estructura en ${DEST_DIR} si no existe..."
mkdir -p "$DEST_DIR"
success "Directorio preparado."

# --- Descargar archivos ---
cd "$DEST_DIR"
for file in $FILES; do
  log "Descargando $file..."
  if wget -q "${REPO_URL}/${file}" -O "$file"; then
    chmod +x "$file"
    success "$file descargado y marcado como ejecutable."
  else
    error "No se pudo descargar $file"
    exit 1
  fi
done

# --- Instrucciones finales ---
echo ""
success "Todos los archivos han sido descargados correctamente."
echo ""
echo "📁 Estás ahora en: $DEST_DIR"
echo ""
echo "🛠️  Para iniciar la instalación del stack domótico, ejecuta:"
echo "   ./setup.sh"
echo ""
echo "🔄 Para actualizar contenedores individualmente, ejecuta:"
echo "   ./update.sh"
echo ""
echo "📦 Para lanzar los servicios manualmente:"
echo "   docker-compose up -d"
echo ""
