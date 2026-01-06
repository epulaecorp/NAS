#!/bin/sh
# ============================================================================
# Script de Mantenimiento y Actualización del Stack Domótico (Synology NAS)
# Autor: epulaecorp + IA
# Versión: 2.1 (autodetectable, robusto, limpieza incluida)
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# CONFIGURACIÓN
# ----------------------------------------------------------------------------
DOCKER_ROOT="/volume1/docker"
COMPOSE_URL="https://raw.githubusercontent.com/epulaecorp/NAS/main/docker-compose.yml"
COMPOSE_FILE="docker-compose.yml"

# UID/GID para permisos
APP_UID=1000
APP_GID=1000

# ----------------------------------------------------------------------------
# LOGGING
# ----------------------------------------------------------------------------
log_info()    { printf "ℹ️  \033[1;34m%s\033[0m\n" "$1"; }
log_success() { printf "✅ \033[1;32m%s\033[0m\n" "$1"; }
log_error()   { printf "❌ \033[1;31m%s\033[0m\n" "$1" >&2; }

# ----------------------------------------------------------------------------
# PRIVILEGIOS
# ----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_info "Se requieren privilegios de administrador. Reintentando con sudo..."
    exec sudo "$0" "$@"
fi

# ----------------------------------------------------------------------------
# DEPENDENCIAS
# ----------------------------------------------------------------------------
command -v docker >/dev/null 2>&1 || {
    log_error "Docker no está instalado (Container Manager)."
    exit 1
}

if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    log_error "Docker Compose no disponible."
    exit 1
fi

# ----------------------------------------------------------------------------
# FUNCIONES
# ----------------------------------------------------------------------------

update_compose_file() {
    log_info "Descargando docker-compose.yml desde GitHub..."
    mkdir -p "$DOCKER_ROOT"

    if ! wget -q "$COMPOSE_URL" -O "$DOCKER_ROOT/$COMPOSE_FILE.tmp"; then
        log_error "No se pudo descargar docker-compose.yml"
        exit 1
    fi

    mv "$DOCKER_ROOT/$COMPOSE_FILE.tmp" "$DOCKER_ROOT/$COMPOSE_FILE"
    log_success "docker-compose.yml actualizado."
}

prepare_volumes_from_compose() {
    log_info "Analizando volúmenes desde docker-compose.yml..."

    cd "$DOCKER_ROOT"

    # Detecta SOLO bind mounts reales en /volume*
    volumes=$(grep -E '^[[:space:]]*-[[:space:]]*/volume' "$COMPOSE_FILE" \
        | grep ':' \
        | sed 's/^[[:space:]]*-[[:space:]]*//' \
        | awk -F: '{print $1}' \
        | sort -u)

    if [ -z "$volumes" ]; then
        log_info "No se detectaron volúmenes bind-mount."
        return
    fi

    echo "$volumes" | while read -r path; do
        if [ ! -d "$path" ]; then
            log_info "Creando directorio: $path"
            mkdir -p "$path"
        fi

        chown -R "$APP_UID:$APP_GID" "$path"
        chmod -R 775 "$path"
    done

    log_success "Estructura de volúmenes preparada."
}

cleanup_docker_images() {
    log_info "Limpiando imágenes Docker no utilizadas..."

    docker image prune -f
    docker image prune -a -f

    log_success "Limpieza de imágenes Docker completada."
}

update_all_services() {
    cd "$DOCKER_ROOT"

    update_compose_file
    prepare_volumes_from_compose

    log_info "Descargando imágenes..."
    eval "$DOCKER_COMPOSE_CMD pull"

    log_info "Levantando contenedores..."
    eval "$DOCKER_COMPOSE_CMD up -d --remove-orphans"

    cleanup_docker_images
}

update_single_service() {
    local service="$1"
    cd "$DOCKER_ROOT"

    update_compose_file
    prepare_volumes_from_compose

    log_info "Actualizando servicio: $service"
    eval "$DOCKER_COMPOSE_CMD pull $service"
    eval "$DOCKER_COMPOSE_CMD up -d --force-recreate $service"

    cleanup_docker_images
}

# ----------------------------------------------------------------------------
# MENÚ
# ----------------------------------------------------------------------------
printf "\n"
log_info "=== Mantenimiento del Stack Domótico (Synology) ==="
printf "1) Actualizar TODOS los servicios\n"
printf "2) Actualizar un servicio individual\n"
printf "3) Solo actualizar docker-compose.yml\n"
printf "4) Salir\n\n"
printf "Selecciona una opción [1-4]: "
read -r choice

case "$choice" in
    1)
        update_all_services
        ;;
    2)
        cd "$DOCKER_ROOT"
        update_compose_file

        services=$(eval "$DOCKER_COMPOSE_CMD config --services")
        i=1
        for s in $services; do
            printf "%2d) %s\n" "$i" "$s"
            i=$((i + 1))
        done

        printf "Selecciona el número del servicio: "
        read -r svc_num

        selected_service=$(echo "$services" | sed -n "${svc_num}p")
        [ -z "$selected_service" ] && {
            log_error "Servicio inválido."
            exit 1
        }

        update_single_service "$selected_service"
        ;;
    3)
        update_compose_file
        prepare_volumes_from_compose
        log_success "docker-compose.yml actualizado y estructura preparada."
        ;;
    4)
        log_info "Saliendo."
        exit 0
        ;;
    *)
        log_error "Opción inválida."
        exit 1
        ;;
esac

printf "\n"
log_success "Proceso finalizado."
printf "\nContenedores activos:\n"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
