#!/bin/sh
# ============================================================================
# Script de instalación para stack domótico, COMPATIBLE CON SYNOLOGY (ash/sh)
# Autor: epulaecorp
# Repositorio: https://github.com/epulaecorp/NAS
# Versión: 3.2 (POSIX Compliant)
# ============================================================================

# 'e' sale en error, 'o pipefail' asegura que los errores en tuberías fallen.
set -eo pipefail

# --- Configuración de rutas ---
DOCKER_ROOT="/volume1/docker"
CONFIG_REPO="https://raw.githubusercontent.com/epulaecorp/NAS/main"

# ============================================================================
# Funciones auxiliares (usando printf para compatibilidad)
# ============================================================================
log_success() { printf "✅ \033[1;32m%s\033[0m\n" "$1"; }
log_info()    { printf "ℹ️ \033[1;34m%s\033[0m\n" "$1"; }
log_warning() { printf "⚠️ \033[1;33m%s\033[0m\n" "$1"; }
log_error()   { printf "❌ \033[1;31m%s\033[0m\n" "$1" >&2; }

safe_download() {
    # wget -q (silencioso) -O (archivo de salida)
    wget -q "$1" -O "$2" || {
        log_error "Fallo al descargar $1"
        return 1
    }
}

update_config_file() {
    local url="$1"
    local dest="$2"
    local filename
    filename=$(basename "$dest")
    
    log_info "Actualizando ${filename}..."
    if safe_download "$url" "$dest"; then
        log_success "${filename} actualizado"
    else
        log_error "Error al actualizar ${filename}"
        exit 1 # Salimos si un archivo de configuración crítico no se puede descargar
    fi
}

# ============================================================================
# Comprobaciones previas
# ============================================================================
log_info "Verificando requisitos del sistema..."

# Forma compatible con POSIX para comprobar si es root
if [ "$(id -u)" -ne 0 ]; then
    log_warning "Este script debe ejecutarse como root. Intentando con sudo..."
    # Si sudo no está disponible o falla, el script se detendrá.
    exec sudo "$0" "$@"
fi

# Detectar el comando de Docker Compose
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="'docker compose'" # Comillas internas para que 'eval' funcione
else
    log_error "docker-compose no encontrado. Instale Docker Compose (plugin o binario)."
    exit 1
fi
log_success "Docker Compose encontrado."

if ! ping -c 1 github.com >/dev/null 2>&1; then
    log_error "Sin conexión a internet. Verifique su conectividad."
    exit 1
fi
log_success "Conexión a internet verificada."

# ============================================================================
# Creación de estructura de directorios
# ============================================================================
log_info "Creando directorios necesarios en ${DOCKER_ROOT}..."
# 'Brace expansion' no es compatible con 'ash', por lo que se expande manualmente.
mkdir -p "${DOCKER_ROOT}/homeassistant"
mkdir -p "${DOCKER_ROOT}/esphome/config"
mkdir -p "${DOCKER_ROOT}/nodered/data"
mkdir -p "${DOCKER_ROOT}/mosquitto/config"
mkdir -p "${DOCKER_ROOT}/mosquitto/data"
mkdir -p "${DOCKER_ROOT}/mosquitto/log"
mkdir -p "${DOCKER_ROOT}/vcode"
mkdir -p "${DOCKER_ROOT}/zigbee2mqtt/data"
mkdir -p "${DOCKER_ROOT}/Updates"
mkdir -p "${DOCKER_ROOT}/music-assistant-server/data"
log_success "Estructura de directorios creada."

# ============================================================================
# Corrección de permisos para volúmenes utilizados por los contenedores
# ============================================================================
log_info "Corrigiendo permisos de volúmenes para contenedores..."
APP_UID=1000
APP_GID=1000
for dir in \
  "${DOCKER_ROOT}/homeassistant" \
  "${DOCKER_ROOT}/esphome/config" \
  "${DOCKER_ROOT}/nodered/data" \
  "${DOCKER_ROOT}/mosquitto/config" \
  "${DOCKER_ROOT}/mosquitto/data" \
  "${DOCKER_ROOT}/mosquitto/log" \
  "${DOCKER_ROOT}/vcode" \
  "${DOCKER_ROOT}/zigbee2mqtt/data" \
  "${DOCKER_ROOT}/music-assistant-server/data"
do
  log_info "Ajustando permisos en $dir"
  chown -R "$APP_UID:$APP_GID" "$dir"
  chmod -R 775 "$dir"
done
log_success "Permisos corregidos para todos los volúmenes."

# ============================================================================
# Descarga y actualización de archivos base
# ============================================================================
cd "${DOCKER_ROOT}"
update_config_file "${CONFIG_REPO}/docker-compose.yml" "docker-compose.yml"
update_config_file "${CONFIG_REPO}/docker-updater.sh" "docker-updater.sh"
chmod +x "docker-updater.sh"

# ============================================================================
# Configuración de Mosquitto
# ============================================================================
log_info "Configurando Mosquitto..."
MOSQUITTO_DIR="${DOCKER_ROOT}/mosquitto/config"
update_config_file "${CONFIG_REPO}/mosquitto/mosquitto.conf" "${MOSQUITTO_DIR}/mosquitto.conf"
update_config_file "${CONFIG_REPO}/mosquitto/pwfile" "${MOSQUITTO_DIR}/pwfile"

# ============================================================================
# Inicio de contenedores
# ============================================================================
log_info "Iniciando servicios con Docker Compose (esto puede tardar varios minutos)..."
# Usamos 'eval' para manejar correctamente el comando 'docker compose' con espacio.
eval $DOCKER_COMPOSE_CMD up -d

# ============================================================================
# Configuraciones personalizadas (post-arranque)
# ============================================================================
log_info "Aplicando configuraciones personalizadas..."
update_config_file "${CONFIG_REPO}/zigbee2mqtt/data/configuration.yaml" "${DOCKER_ROOT}/zigbee2mqtt/data/configuration.yaml"
update_config_file "${CONFIG_REPO}/nodered/data/settings.js" "${DOCKER_ROOT}/nodered/data/settings.js"

# ============================================================================
# Post-instalación (comandos dentro de los contenedores)
# ============================================================================
log_info "Instalando HACS en Home Assistant..."
if docker exec homeassistant sh -c "wget -q -O - https://get.hacs.xyz | bash -"; then
    docker restart homeassistant
    log_success "HACS instalado correctamente."
else
    log_error "Error instalando HACS. Puede que el contenedor aún no estuviera listo. Intente manualmente."
fi

log_info "Instalando temas en Node-RED..."
if docker exec nodered sh -c "npm install --prefix /data @node-red-contrib-themes/theme-collection"; then
    docker restart nodered
    log_success "Temas instalados correctamente."
else
    log_error "Error instalando temas en Node-RED."
fi

# ============================================================================
# Gestión de permisos finales
# ============================================================================
log_info "Ajustando permisos finales..."
chown -R root:root "${DOCKER_ROOT}/music-assistant-server/data"
chmod 775 "${DOCKER_ROOT}/music-assistant-server/data"
log_success "Permisos ajustados."

# ============================================================================
# Finalización
# ============================================================================
log_info "Reiniciando servicios finales para aplicar cambios..."
docker restart mosquitto zigbee2mqtt

log_success "¡Instalación completada exitosamente!"
printf "\nResumen de contenedores:\n"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Mostrar IP preferida
LAN_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

# Información de acceso
printf "\n\033[1;35mAcceso a los servicios:\033[0m\n"
printf "Home Assistant:     http://%s:8123\n" "$LAN_IP"
printf "Node-RED:           http://%s:1880\n" "$LAN_IP"
printf "VS Code:            http://%s:8443\n" "$LAN_IP"
printf "Zigbee2MQTT:        http://%s:8080\n" "$LAN_IP"
printf "ESPHome:            http://%s:6052\n" "$LAN_IP"
printf "Music Assistant:    http://%s:8095\n" "$LAN_IP"
printf "\nPara administrar actualizaciones, usa el comando:\n\033[1;32m./docker-updater.sh\033[0m\n"
