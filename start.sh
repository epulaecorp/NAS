#!/bin/sh
# ============================================================================
# Script de arranque para stack domótico en Synology NAS - Versión 2.1
# ============================================================================
# 
# 📌 USO RECOMENDADO (3 métodos):
#
# 1. Ejecución directa desde GitHub:
#    wget -qO- "https://raw.githubusercontent.com/epulaecorp/NAS/main/start.sh" | sudo sh
#
# 2. Descargar y ejecutar localmente:
#    wget --no-check-certificate -O /volume1/scripts/start.sh "https://raw.githubusercontent.com/epulaecorp/NAS/main/start.sh"
#    chmod +x /volume1/scripts/start.sh
#    sudo /volume1/scripts/start.sh
#
# 3. Modo depuración (ver pasos detallados):
#    wget -O /tmp/start_debug.sh "https://raw.githubusercontent.com/epulaecorp/NAS/main/start.sh"
#    chmod +x /tmp/start_debug.sh
#    sudo sh -x /tmp/start_debug.sh
#
# 🔧 REQUISITOS:
# - Synology NAS con acceso SSH
# - Permisos de administrador (sudo)
# - Conexión a internet
# - Paquete 'wget' instalado (sudo synopkg install wget)
#
# ⚠️ ADVERTENCIAS:
# - Este script modificará el directorio /volume1/docker
# - Requiere 100MB de espacio disponible
# - Verifica siempre el código antes de ejecutar scripts remotos
#
# 🔗 REPOSITORIO:
# https://github.com/epulaecorp/NAS
#
# ============================================================================

# --- Verificaciones previas (no editables) ---
[ "$(id -u)" -ne 0 ] && { echo "✖ Ejecuta con privilegios sudo"; exit 1; }
[ ! -d "/volume1" ] && { echo "✖ Sistema no compatible: Directorio /volume1 no encontrado"; exit 1; }

# --- Configuración (personalizable) ---
REPO_URL="https://raw.githubusercontent.com/epulaecorp/NAS/main"
DEST_DIR="/volume1/docker"          # Directorio de instalación
FILES="docker-compose.yml setup.sh updater.sh"  # Archivos a descargar
REQUIRED_SPACE=100                  # Espacio mínimo requerido (MB)

# --- Funciones (no modificar) ---
log() { printf "\033[1;34m[ℹ]\033[0m %s\n" "$1"; }
success() { printf "\033[1;32m[✓]\033[0m %s\n" "$1"; }
error() { printf "\033[1;31m[✗]\033[0m %s\n" "$1" >&2; }

check_space() {
  local available=$(df -m "$DEST_DIR" | awk 'NR==2 {print $4}')
  [ "$available" -lt "$REQUIRED_SPACE" ] && {
    error "Espacio insuficiente: $available MB disponibles < $REQUIRED_SPACE MB requeridos"
    return 1
  }
}

# --- Ejecución principal ---
set -e  # Modo estricto

log "Iniciando instalación $(date '+%Y-%m-%d %H:%M:%S')"
log "Verificando dependencias..."

# 1. Verificar paquetes
for cmd in wget docker docker-compose; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Falta dependencia: $cmd"
    case "$cmd" in
      wget) echo "  Solución: sudo synopkg install wget";;
      docker) echo "  Solución: Instalar Docker desde el Centro de Paquetes";;
      *) echo "  Solución: Contactar al administrador";;
    esac
    exit 1
  fi
done

# 2. Verificar espacio
check_space || exit 1

# 3. Preparar directorio
log "Preparando directorio $DEST_DIR..."
mkdir -p "$DEST_DIR"
chmod 755 "$DEST_DIR"
cd "$DEST_DIR" || exit 1

# 4. Descargar archivos
for file in $FILES; do
  log "Obteniendo $file..."
  if wget --no-check-certificate -q "${REPO_URL}/${file}" -O "${file}.new"; then
    [ -f "$file" ] && mv "$file" "$file.bak"  # Backup
    mv "${file}.new" "$file"
    [[ "$file" == *.sh ]] && chmod +x "$file"
    success "$file instalado"
  else
    error "Falló la descarga de $file"
    [ -f "${file}.new" ] && rm -f "${file}.new"
    exit 1
  fi
done

# --- Post-instalación ---
success "Instalación completada en $DEST_DIR"
echo "
🛠  COMANDOS DISPONIBLES:
   ./setup.sh       - Configuración inicial
   ./updater.sh     - Gestión de actualizaciones
   docker-compose up -d - Iniciar contenedores

📝 NOTAS:
- Revisa docker-compose.yml antes de iniciar
- Los backups terminan con extensión .bak
- Para reinstalar: sudo rm -f $DEST_DIR/*.sh $DEST_DIR/*.yml
"
