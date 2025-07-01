#!/bin/sh
# Script interactivo para actualizar servicios Docker, compatible con Synology (ash/sh).
# Versión 4: Corregido el problema de 'echo -e' usando 'printf' para máxima compatibilidad.

# --- Configuración de seguridad y manejo de errores ---
set -e
set -o pipefail
trap "printf '\n\e[31mActualización cancelada. Saliendo del script.\e[0m\n\n'; exit 1" INT

# --- Variables de configuración ---
DOCKER_COMPOSE_RAW_URL="https://raw.githubusercontent.com/epulaecorp/NAS/main/docker-compose.yml"
DOCKER_COMPOSE_FILE="docker-compose.yml"
UPDATE_LOG_DIR="Updates"
UPDATE_LOG_FILE="${UPDATE_LOG_DIR}/update.log"
MANUAL_SERVICES="homeassistant mosquitto zigbee2mqtt watchtower nodered esphome codeserver music-assistant-server"

# --- Comprobaciones de Prerrequisitos ---
if ! command -v curl >/dev/null 2>&1; then
    printf "\e[31mERROR:\e[0m El comando 'curl' es necesario y no está instalado.\n" >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    printf "\e[31mERROR:\e[0m Docker no está instalado o no se encuentra en el PATH.\n" >&2
    exit 1
fi

# --- Funciones ---

download_compose_file() {
    printf -- "--- Descargando la última versión de '${DOCKER_COMPOSE_FILE}' desde el repositorio ---\n"
    if ! curl -sSf -o "${DOCKER_COMPOSE_FILE}" "${DOCKER_COMPOSE_RAW_URL}"; then
        printf "\e[31mERROR:\e[0m No se pudo descargar el archivo desde '${DOCKER_COMPOSE_RAW_URL}'.\n" >&2
        printf "Por favor, verifica la URL y tu conexión a internet.\n" >&2
        exit 1
    fi
    printf "\e[32mArchivo '${DOCKER_COMPOSE_FILE}' descargado/actualizado correctamente.\e[0m\n"
}


# Función para corregir permisos en contenedores clave
fix_permissions() {
  container="$1"
  path="$2"
  if docker ps -q -f name="$container" | grep -q .; then
    echo "🔧 Corrigiendo permisos en $path dentro de $container..."
    docker exec "$container" chown -R 1000:1000 "$path"
  else
    echo "⚠️ Contenedor $container no está corriendo. Saltando corrección de permisos."
  fi
}

# Inicializar listas de éxito y fallo
UPDATED_SERVICES=""
FAILED_SERVICES=""
update_service() {
    local service_name="$1"
    printf "\n=== Iniciando actualización para: \e[1m%s\e[0m ===\n" "$service_name"

    if ! grep -qE "^\s{2,}${service_name}:" "$DOCKER_COMPOSE_FILE"; then
        printf "\e[31mERROR:\e[0m El servicio '%s' no está definido en %s.\n" "$service_name" "$DOCKER_COMPOSE_FILE"
        return 1
    fi

    case "$service_name" in
  nodered)
    fix_permissions nodered /data
    ;;
  esphome)
    fix_permissions esphome /config
    ;;
  codeserver)
    fix_permissions codeserver /config
    ;;
        music-assistant-server)
            printf "\e[33m⚠️  Advertencia: Music Assistant requiere configuración especial\e[0m\n"
            printf "¿Continuar con la actualización? (y/N): "
            read confirm_ma
            case "$confirm_ma" in
                [Yy]*) ;; 
                *)
                    printf "\e[33mActualización de Music Assistant cancelada.\e[0m\n"
                    return 0
                    ;;
            esac
            ;;
    esac

    printf "Descargando la imagen más reciente para %s...\n" "$service_name"
    if ! eval $DOCKER_COMPOSE_CMD -f "\"${DOCKER_COMPOSE_FILE}\"" pull "\"${service_name}\""; then
        printf "\e[31mERROR:\e[0m No se pudo descargar la nueva imagen para %s.\n" "$service_name"
        return 1
    fi

    printf "Recreando el contenedor de %s...\n" "$service_name"
    if ! eval $DOCKER_COMPOSE_CMD -f "\"${DOCKER_COMPOSE_FILE}\"" up -d --no-deps --force-recreate "\"${service_name}\""; then
        printf "\e[31mERROR:\e[0m No se pudo recrear %s.\n" "$service_name"
        return 1
    fi

    case "$service_name" in
        homeassistant)
            printf "\e[33mℹ️  Se recomienda ejecutar 'docker restart homeassistant' después de actualizar\e[0m\n"
            ;;
        music-assistant-server)
            printf "\e[33mℹ️  Verificando permisos para Music Assistant...\e[0m\n"
            if docker inspect -f '{{.State.Running}}' music-assistant-server >/dev/null 2>&1; then
                docker exec music-assistant-server chown -R root:root /data
            else
                printf "\e[33mAdvertencia: No se pudo ejecutar el post-procesamiento en Music Assistant.\e[0m\n"
            fi
            ;;
    esac

    echo "$(date +'%F %T') - Servicio actualizado: ${service_name}" >> "${UPDATE_LOG_FILE}"
    printf "=== \e[32m%s actualizado correctamente.\e[0m ===\n" "$service_name"
    return 0
}

# --- Lógica principal ---

if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="'docker compose'"
else
    printf "\e[31mERROR: No se encontró un comando funcional de Docker Compose.\e[0m\n" >&2
    exit 1
fi

mkdir -p "$UPDATE_LOG_DIR"
download_compose_file

printf "\n--- GESTOR DE ACTUALIZACIONES MANUALES DE DOCKER COMPOSE ---\n"

while true; do
    printf "\n--- MENÚ DE ACTUALIZACIÓN ---\n"
    printf "Selecciona el servicio a actualizar, '0' para todos, o 'q' para salir:\n"
    printf "  \e[1m0)\e[0m Actualizar TODOS los servicios listados\n"
    
    i=1
    for service in $MANUAL_SERVICES; do
        if [ "$service" = "music-assistant-server" ]; then
            printf "  \e[1m%s)\e[0m \e[33m%s (requisitos especiales)\e[0m\n" "$i" "$service"
        else
            printf "  \e[1m%s)\e[0m %s\n" "$i" "$service"
        fi
        i=$(expr $i + 1)
    done
    SERVICE_COUNT=$(expr $i - 1)

    printf "  \e[1mq)\e[0m Salir\n"
    printf "Tu elección: "
    read choice

    case "$choice" in
        0)
            printf "¿Estás seguro de que quieres actualizar TODOS los servicios? (y/N): "
            read confirm_all
            case "$confirm_all" in
                [Yy]*)
                    printf "\nIniciando actualizaciones...\n"
                    for service in $MANUAL_SERVICES; do
                        update_service "$service" || printf "\e[31mFallo al actualizar %s. Continuando...\e[0m\n" "$service"
                    done
                    printf "\n\e[32mTodas las actualizaciones han sido procesadas.\e[0m\n"
                    break
                    ;;
                *)
                    printf "Actualización cancelada.\n"
                    continue
                    ;;
            esac
            ;;
        [1-9] | [1-9][0-9])
            if [ "$choice" -gt 0 ] && [ "$choice" -le "$SERVICE_COUNT" ]; then
                selected_service=$(echo "$MANUAL_SERVICES" | cut -d' ' -f"$choice")
                
                printf "¿Estás seguro de que quieres actualizar %s? (y/N): " "$selected_service"
                read confirm_single
else
  printf "⚠️ Opción fuera de rango. Intenta de nuevo.\n"
  continue
                case "$confirm_single" in
                    [Yy]*)
                        update_service "$selected_service" || printf "\e[31mFallo al actualizar %s.\e[0m\n" "$selected_service"
                        break
                        ;;
                    *)
                        printf "Actualización cancelada.\n"
                        continue
                        ;;
                esac
            else
                printf "\e[31mERROR:\e[0m Opción inválida.\n"
            fi
            ;;
        [Qq])
            printf "Saliendo del script.\n"
            break
            ;;
        *)
            printf "\e[31mERROR:\e[0m Opción inválida.\n"
            ;;
    esac
done

# --- Limpieza opcional ---
printf "\n--------------------------------------------------\n"
printf "¿Deseas limpiar imágenes no utilizadas (docker image prune)? (y/N): "
read cleanup_confirm
case "$cleanup_confirm" in
    [Yy]*)
        printf "Ejecutando limpieza...\n"
        docker image prune -f
        printf "\e[32mLimpieza completada.\e[0m\n"
        ;;
    *)
        printf "Limpieza omitida.\n"
        ;;
esac


echo "\nResumen de actualización:"
echo "Servicios actualizados con éxito: $UPDATED_SERVICES"
echo "Servicios con errores: $FAILED_SERVICES"
printf "\nScript finalizado.\n\n"
