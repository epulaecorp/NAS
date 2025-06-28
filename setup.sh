#!/bin/bash

# ============================================================================
# Script de instalación para stack domótico en Docker (Home Assistant, ESPHome,
# Node-RED, Mosquitto, Zigbee2MQTT, VSCode y Music Assistant)
# Autor: epulaecorp
# Repositorio: https://github.com/epulaecorp/NAS
# Fecha: 2025-06-01
# Versión: 3.1
# ============================================================================

set -euo pipefail

# Configuración de rutas
DOCKER_ROOT="/volume1/docker"
CONFIG_REPO="https://raw.githubusercontent.com/epulaecorp/NAS/main"

# ============================================================================
# Funciones auxiliares
# ============================================================================
log_success() { echo -e "✅ \033[1;32m$1\033[0m"; }
log_info()    { echo -e "ℹ️ \033[1;34m$1\033[0m"; }
log_warning() { echo -e "⚠️ \033[1;33m$1\033[0m"; }
log_error()   { echo -e "❌ \033[1;31m$1\033[0m" >&2; }

safe_download() {
    wget -q --show-progress --tries=3 --timeout=30 "$1" -O "$2" || {
        log_error "Fallo al descargar $1"
        return 1
    }
}

update_config_file() {
    local url="$1"
    local dest="$2"
    log_info "Actualizando $(basename "$dest")..."
    safe_download "$url" "$dest" && \
        log_success "$(basename "$dest") actualizado" || \
        log_error "Error al actualizar $(basename "$dest")"
}

# ============================================================================
# Comprobaciones previas
# ============================================================================
log_info "Verificando requisitos del sistema..."

if [[ $EUID -ne 0 ]]; then
    log_warning "Este script debe ejecutarse como root. Intentando con sudo..."
    exec sudo "$0" "$@"
fi

if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
    log_error "docker-compose no encontrado. Instale Docker Compose (plugin o binario clásico)."
    exit 1
fi

if ! ping -c 1 github.com &> /dev/null; then
    log_error "Sin conexión a internet. Verifique su conectividad."
    exit 1
fi

DOCKER_COMPOSE="docker-compose"
command -v docker compose &> /dev/null && DOCKER_COMPOSE="docker compose"

# ============================================================================
# Creación de estructura de directorios
# ============================================================================
log_info "Creando directorios necesarios..."
mkdir -p "${DOCKER_ROOT}/"{homeassistant,esphome/config,nodered/data,mosquitto/{config,data,log},vcode,zigbee2mqtt/data,Updates,music-assistant-server/data}

# ============================================================================
# Descarga y actualización de archivos base
# ============================================================================
cd "${DOCKER_ROOT}"
update_config_file "${CONFIG_REPO}/docker-compose.yml" "docker-compose.yml"
update_config_file "${CONFIG_REPO}/docker-updater.sh" "docker-updater.sh"
chmod +x docker-updater.sh

# ============================================================================
# Configuración de Mosquitto
# ============================================================================
log_info "Configurando Mosquitto..."
MOSQUITTO_DIR="${DOCKER_ROOT}/mosquitto/config"
mkdir -p "${MOSQUITTO_DIR}"
update_config_file "${CONFIG_REPO}/mosquitto/mosquitto.conf" "${MOSQUITTO_DIR}/mosquitto.conf"
update_config_file "${CONFIG_REPO}/mosquitto/pwfile" "${MOSQUITTO_DIR}/pwfile"

# ============================================================================
# Gestión de permisos
# ============================================================================
log_info "Ajustando permisos..."
find "${DOCKER_ROOT}" -type d -exec chmod 775 {} \;
find "${DOCKER_ROOT}" -type f -exec chmod 664 {} \;
chmod +x "${DOCKER_ROOT}/docker-updater.sh"

# ============================================================================
# Inicio de contenedores
# ============================================================================
log_info "Iniciando servicios con Docker Compose..."
${DOCKER_COMPOSE} up -d --pull always --build

# ============================================================================
# Configuraciones personalizadas
# ============================================================================
log_info "Configurando Zigbee2MQTT..."
update_config_file "${CONFIG_REPO}/zigbee2mqtt/data/configuration.yaml" "${DOCKER_ROOT}/zigbee2mqtt/data/configuration.yaml"

log_info "Configurando Node-RED..."
update_config_file "${CONFIG_REPO}/nodered/data/settings.js" "${DOCKER_ROOT}/nodered/data/settings.js"

# ============================================================================
# Post-instalación
# ============================================================================
log_info "Instalando HACS en Home Assistant..."
docker exec homeassistant bash -c "wget -q -O - https://get.hacs.xyz | bash -" && \
docker restart homeassistant && \
log_success "HACS instalado correctamente" || \
log_error "Error instalando HACS"

log_info "Instalando temas en Node-RED..."
docker exec nodered bash -c "npm install @node-red-contrib-themes/theme-collection" && \
docker restart nodered && \
log_success "Temas instalados correctamente" || \
log_error "Error instalando temas"

# ============================================================================
# Configuración especial para Music Assistant
# ============================================================================
log_info "Configurando permisos especiales para Music Assistant..."
chmod 775 "${DOCKER_ROOT}/music-assistant-server/data"
chown -R root:root "${DOCKER_ROOT}/music-assistant-server/data"

# ============================================================================
# Finalización
# ============================================================================
log_info "Reiniciando servicios finales..."
docker restart mosquitto zigbee2mqtt music-assistant-server

log_success "Instalación completada exitosamente!"
echo -e "\nResumen de contenedores:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Mostrar IP preferida
LAN_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

# Información de acceso
echo -e "\n\033[1;35mAcceso a los servicios:\033[0m"
echo "Home Assistant:     http://${LAN_IP}:8123"
echo "Node-RED:           http://${LAN_IP}:1880"
echo "VS Code:            http://${LAN_IP}:8443"
echo "Zigbee2MQTT:        http://${LAN_IP}:8080"
echo "ESPHome:            http://${LAN_IP}:6052"
echo "Music Assistant:    http://${LAN_IP}:8095"
echo -e "\nPara administrar actualizaciones: ./docker-updater.sh"
