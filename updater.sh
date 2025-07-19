#!/bin/sh
# ============================================================================
# Script de Mantenimiento y Actualización para Stack Domótico en Synology
# Autor: Asistente de IA (basado en petición y estilo de epulaecorp)
# Versión: 1.1 (con soporte para Wyoming Piper/Whisper)
#
# Funcionalidades:
# - Menú interactivo para seleccionar la acción.
# - Actualizar todos los contenedores.
# - Actualizar/Reparar un contenedor individual.
# - Siempre usa el último 'docker-compose.yml' de GitHub.
# - Re-aplica permisos a los volúmenes después de la operación.
# - Limpia imágenes de Docker no utilizadas.
# ============================================================================

# 'e' sale en error, 'u' sale en variable no definida, 'o pipefail' asegura que los errores en tuberías fallen.
set -euo pipefail

# --- Configuración de rutas y URLs ---
DOCKER_ROOT="/volume1/docker"
COMPOSE_URL="https://raw.githubusercontent.com/epulaecorp/NAS/main/docker-compose.yml"
COMPOSE_FILE="docker-compose.yml"
# UID/GID que se aplicará a los volúmenes
APP_UID=1000
APP_GID=1000

# --- Colores y Funciones de Log ---
log_success() { printf "✅ \033[1;32m%s\033[0m\n" "$1"; }
log_info()    { printf "ℹ️ \033[1;34m%s\033[0m\n" "$1"; }
log_error()   { printf "❌ \033[1;31m%s\033[0m\n" "$1" >&2; }

# --- Verificación de Privilegios y Requisitos ---
if [ "$(id -u)" -ne 0 ]; then
    log_info "Se requieren privilegios de administrador. Intentando con sudo..."
    exec sudo "$0" "$@"
fi

if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker no encontrado. Asegúrate de que 'Container Manager' está instalado."
    exit 1
fi

if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    log_error "Docker Compose no encontrado."
    exit 1
fi

# --- Funciones Principales ---

update_compose_file() {
    log_info "Descargando la última versión de '$COMPOSE_FILE' desde GitHub..."
    if ! wget -q "$COMPOSE_URL" -O "$DOCKER_ROOT/$COMPOSE_FILE.tmp"; then
        log_error "Fallo al descargar el archivo docker-compose.yml. Abortando."
        rm -f "$DOCKER_ROOT/$COMPOSE_FILE.tmp"
        exit 1
    fi
    mv "$DOCKER_ROOT/$COMPOSE_FILE.tmp" "$DOCKER_ROOT/$COMPOSE_FILE"
    log_success "'$COMPOSE_FILE' actualizado correctamente."
}

fix_permissions() {
    local service_name=$1
    local service_volume_path=""

    log_info "Re-aplicando permisos para el servicio '$service_name'..."

    # Mapeo de servicios a sus rutas de volumen principales
    case $service_name in
        homeassistant) service_volume_path="${DOCKER_ROOT}/homeassistant" ;;
        esphome) service_volume_path="${DOCKER_ROOT}/esphome" ;;
        nodered) service_volume_path="${DOCKER_ROOT}/nodered" ;;
        mosquitto) service_volume_path="${DOCKER_ROOT}/mosquitto" ;;
        zigbee2mqtt) service_volume_path="${DOCKER_ROOT}/zigbee2mqtt" ;;
        codeserver|vcode) service_volume_path="${DOCKER_ROOT}/vcode" ;;
        music-assistant-server) service_volume_path="${DOCKER_ROOT}/music-assistant-server" ;;
        # ▼▼▼ CAMBIO: Añadir mapeo para Piper y Whisper ▼▼▼
        piper) service_volume_path="${DOCKER_ROOT}/piper-data" ;;
        whisper) service_volume_path="${DOCKER_ROOT}/whisper-data" ;;
        # ▲▲▲ FIN DEL CAMBIO ▲▲▲
        all)
            log_info "Aplicando permisos a todos los volúmenes conocidos..."
            # Llama a esta misma función para cada servicio individual
            # ▼▼▼ CAMBIO: Añadir los nuevos servicios a la lista de "todos" ▼▼▼
            for srv in homeassistant esphome nodered mosquitto zigbee2mqtt vcode music-assistant-server piper whisper; do
            # ▲▲▲ FIN DEL CAMBIO ▲▲▲
                fix_permissions "$srv"
            done
            return
            ;;
        *)
            log_error "Servicio '$service_name' desconocido para la corrección de permisos."
            return 1
            ;;
    esac

    if [ -d "$service_volume_path" ]; then
        chown -R "$APP_UID:$APP_GID" "$service_volume_path"
        chmod -R 775 "$service_volume_path"
        log_success "Permisos ajustados para $service_volume_path"
    else
        log_error "El directorio de volumen '$service_volume_path' no existe."
    fi
}

cleanup_docker() {
    log_info "Limpiando imágenes de Docker no utilizadas..."
    if docker image prune -a -f; then
        log_success "Limpieza de imágenes completada."
    else
        log_error "Ocurrió un error durante la limpieza de imágenes."
    fi
}

update_or_repair_service() {
    local service_name=$1
    
    log_info "Iniciando proceso de actualización/reparación para: '$service_name'..."
    cd "$DOCKER_ROOT"

    log_info "Paso 1: Descargando las últimas imágenes para '$service_name'..."
    if ! eval "$DOCKER_COMPOSE_CMD pull $service_name"; then
        log_error "Fallo al descargar la imagen para '$service_name'. Abortando."
        exit 1
    fi

    log_info "Paso 2: Re-creando el contenedor para '$service_name'..."
    if ! eval "$DOCKER_COMPOSE_CMD up -d --remove-orphans --force-recreate $service_name"; then
        log_error "Fallo al re-crear el contenedor '$service_name'. Abortando."
        exit 1
    fi

    log_success "Servicio '$service_name' actualizado/reparado correctamente."
    
    # Solo aplicamos permisos si no es la opción "all"
    if [ "$service_name" != "all" ]; then
        fix_permissions "$service_name"
    fi
}

# --- Menú Interactivo ---
display_menu() {
    printf "\n"
    log_info "=== Script de Mantenimiento del Stack de Domótica ==="
    printf "Selecciona una opción:\n"
    printf "  \033[1;32m1)\033[0m Actualizar/Reparar TODOS los servicios\n"
    printf "  \033[1;32m2)\033[0m Actualizar/Reparar un servicio INDIVIDUAL\n"
    printf "  \033[1;33m3)\033[0m Solo descargar el último 'docker-compose.yml'\n"
    printf "  \033[1;31m4)\033[0m Salir\n"
    printf "\n"
}

# ▼▼▼ CAMBIO: Añadir los nuevos servicios a la lista para el menú interactivo ▼▼▼
SERVICES="homeassistant esphome nodered mosquitto zigbee2mqtt codeserver music-assistant-server piper whisper watchtower"
# ▲▲▲ FIN DEL CAMBIO ▲▲▲

display_menu
printf "Introduce tu elección [1-4]: "
read -r choice

case $choice in
    1)
        log_info "Has elegido actualizar/reparar TODOS los servicios."
        update_compose_file
        # El comando 'up' sin especificar servicio, actualiza todo lo que ha cambiado.
        log_info "Descargando todas las imágenes nuevas..."
        eval "$DOCKER_COMPOSE_CMD pull"
        log_info "Aplicando actualizaciones a todos los contenedores..."
        eval "$DOCKER_COMPOSE_CMD up -d --remove-orphans"
        log_success "Todos los servicios han sido actualizados."
        fix_permissions "all"
        cleanup_docker
        ;;
    2)
        log_info "Has elegido actualizar/reparar un servicio individual."
        printf "Servicios disponibles:\n"
        i=1
        for srv in $SERVICES; do
            printf "  \033[1;32m%s)\033[0m %s\n" "$i" "$srv"
            i=$((i + 1))
        done
        printf "Introduce el número del servicio: "
        read -r service_choice
        
        # Validar entrada
        if ! [ "$service_choice" -ge 1 ] 2>/dev/null || ! [ "$service_choice" -le $(echo "$SERVICES" | wc -w) ] 2>/dev/null; then
             log_error "Opción no válida."
             exit 1
        fi
        
        selected_service=$(echo "$SERVICES" | cut -d' ' -f"$service_choice")
        
        update_compose_file
        update_or_repair_service "$selected_service"
        cleanup_docker
        ;;
    3)
        log_info "Has elegido solo actualizar 'docker-compose.yml'."
        cd "$DOCKER_ROOT"
        update_compose_file
        log_info "Puedes aplicar los cambios ejecutando este script de nuevo y eligiendo la opción 1 o 2."
        ;;
    4)
        log_info "Saliendo del script."
        exit 0
        ;;
    *)
        log_error "Opción no válida. Por favor, introduce un número entre 1 y 4."
        exit 1
        ;;
esac

log_success "\nProceso de mantenimiento finalizado."
printf "\nResumen de contenedores actuales:\n"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
