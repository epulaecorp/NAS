#!/bin/bash

# ============================================================================
# Script de instalación para stack domótico en Docker (Home Assistant, ESPHome,
# Node-RED, Mosquitto, Zigbee2MQTT, VSCode y Music Assistant)
# Autor: epulaecorp
# Repositorio: https://github.com/epulaecorp/NAS
# Fecha: 2025-06-01
# Versión: 3.0
# ============================================================================

set -euo pipefail  # Detener script ante errores, variables no definidas y capturar errores en pipes

# Configuración de rutas
DOCKER_ROOT="/volume1/docker"
CONFIG_REPO="https://raw.githubusercontent.com/epulaecorp/NAS/main"

# ============================================================================
# Funciones auxiliares
# ============================================================================
log_success() {
    echo -e "✅ \033[1;32m$1\033[0m"
}

log_info() {
    echo -e "ℹ️ \033[1;34m$1\033[0m"
}

log_warning() {
    echo -e "⚠️ \033[1;33m$1\033[0m"
}

log_error() {
    echo -e "❌ \033[1;31m$1\033[0m" >&2
}

safe_download() {
    wget -q --show-progress --tries=3 --timeout=30 "$1" -O "$2" || {
        log_error "Fallo al descargar $1"
        return 1
    }
}

# ============================================================================
# Comprobaciones previas
# ============================================================================
log_info "Verificando requisitos del sistema..."

# Comprobar si somos root
if [[ $EUID -ne 0 ]]; then
    log_warning "Este script debe ejecutarse como root. Intentando con sudo..."
    exec sudo "$0" "$@"
fi

# Verificar existencia de docker-compose
if ! command -v docker-compose &> /dev/null; then
    log_error "docker-compose no encontrado. Instale primero Docker y docker-compose."
    exit 1
fi

# Verificar conectividad a internet
if ! ping -c 1 github.com &> /dev/null; then
    log_error "Sin conexión a internet. Verifique su conectividad."
    exit 1
fi

# ============================================================================
# Creación de estructura de directorios
# ============================================================================
log_info "Creando directorios necesarios..."
mkdir -p "${DOCKER_ROOT}/"{homeassistant,esphome/config,nodered/data,mosquitto/{config,data,log},vcode,zigbee2mqtt/data,Updates,music-assistant-server/data}

# ============================================================================
# Descarga de archivos base
# ============================================================================
log_info "Descargando archivos de configuración base..."
cd "${DOCKER_ROOT}"

# Descargar docker-compose.yml si no existe
if [[ ! -f docker-compose.yml ]]; then
    safe_download "${CONFIG_REPO}/docker-compose.yml" "docker-compose.yml"
else
    log_warning "docker-compose.yml ya existe. Se conservará la versión actual."
fi

# Descargar script de actualización
safe_download "${CONFIG_REPO}/docker-updater.sh" "docker-updater.sh"
chmod +x docker-updater.sh

# ============================================================================
# Configuración de Mosquitto
# ============================================================================
log_info "Configurando Mosquitto..."
MOSQUITTO_DIR="${DOCKER_ROOT}/mosquitto/config"
mkdir -p "${MOSQUITTO_DIR}"

safe_download "${CONFIG_REPO}/mosquitto/mosquitto.conf" "${MOSQUITTO_DIR}/mosquitto.conf"
safe_download "${CONFIG_REPO}/mosquitto/pwfile" "${MOSQUITTO_DIR}/pwfile"

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
docker-compose up -d --pull always --build

# ============================================================================
# Configuraciones personalizadas
# ============================================================================
# Zigbee2MQTT
log_info "Configurando Zigbee2MQTT..."
Z2M_CONFIG="${DOCKER_ROOT}/zigbee2mqtt/data/configuration.yaml"
safe_download "${CONFIG_REPO}/zigbee2mqtt/data/configuration.yaml" "${Z2M_CONFIG}"

# Node-RED
log_info "Configurando Node-RED..."
NR_CONFIG="${DOCKER_ROOT}/nodered/data/settings.js"
safe_download "${CONFIG_REPO}/nodered/data/settings.js" "${NR_CONFIG}"

# ============================================================================
# Post-instalación
# ============================================================================
# Instalación HACS
log_info "Instalando HACS en Home Assistant..."
docker exec homeassistant bash -c "wget -q -O - https://get.hacs.xyz | bash -" && \
docker restart homeassistant && \
log_success "HACS instalado correctamente" || \
log_error "Error instalando HACS"

# Tema Node-RED
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

# Información de acceso
echo -e "\n\033[1;35mAcceso a los servicios:\033[0m"
echo "Home Assistant:     http://$(hostname -I | cut -d' ' -f1):8123"
echo "Node-RED:           http://$(hostname -I | cut -d' ' -f1):1880"
echo "VS Code:            http://$(hostname -I | cut -d' ' -f1):8443"
echo "Zigbee2MQTT:        http://$(hostname -I | cut -d' ' -f1):8080"
echo "ESPHome:            http://$(hostname -I | cut -d' ' -f1):6052"
echo "Music Assistant:    http://$(hostname -I | cut -d' ' -f1):8095"
echo -e "\nPara administrar actualizaciones: ./docker-updater.sh"
