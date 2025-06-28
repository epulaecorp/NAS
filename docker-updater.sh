#!/bin/sh
# Script interactivo para actualizar servicios Docker, compatible con Synology (ash/sh).
# Versión 3: Totalmente compatible con POSIX sh, sin 'bashisms'.

# --- Configuración de seguridad y manejo de errores ---
set -e
set -o pipefail
trap "echo '\n\e[31mActualización cancelada. Saliendo del script.\e[0m\n'; exit 1" INT

# --- Variables de configuración ---
DOCKER_COMPOSE_RAW_URL="https://raw.githubusercontent.com/epulaecorp/NAS/main/docker-compose.yml"
DOCKER_COMPOSE_FILE="docker-compose.yml"
UPDATE_LOG_DIR="Updates"
UPDATE_LOG_FILE="${UPDATE_LOG_DIR}/update.log"
# Convertido a una cadena de texto para compatibilidad con 'ash'
MANUAL_SERVICES="homeassistant mosquitto zigbee2mqtt watchtower nodered esphome codeserver music-assistant-server"

# --- Comprobaciones de Prerrequisitos ---
if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: El comando 'curl' es necesario y no está instalado." >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker no está instalado o no se encuentra en el PATH." >&2
    exit 1
fi

# --- Funciones ---

# Función para descargar el archivo docker-compose.yml
download_compose_file() {
    echo "--- Descargando la última versión de '${DOCKER_COMPOSE_FILE}' desde el repositorio ---"
    if ! curl -sSf -o "${DOCKER_COMPOSE_FILE}" "${DOCKER_COMPOSE_RAW_URL}"; then
        echo "ERROR: No se pudo descargar el archivo desde '${DOCKER_COMPOSE_RAW_URL}'." >&2
        echo "Por favor, verifica la URL y tu conexión a internet." >&2
        exit 1
    fi
    echo "\e[32mArchivo '${DOCKER_COMPOSE_FILE}' descargado/actualizado correctamente.\e[0m"
}

# Función para actualizar un servicio
update_service() {
    local service_name="$1"
    echo "\n=== Iniciando actualización para: \e[1m${service_name}\e[0m ==="

    if ! grep -qE "^\s{2,}${service_name}:" "$DOCKER_COMPOSE_FILE"; then
        echo "\e[31mERROR:\e[0m El servicio '${service_name}' no está definido en ${DOCKER_COMPOSE_FILE}."
        return 1
    fi

    # Usamos 'case' en lugar de 'if' para compatibilidad
    case "$service_name" in
        music-assistant-server)
            echo "\e[33m⚠️  Advertencia: Music Assistant requiere configuración especial\e[0m"
            printf "¿Continuar con la actualización? (y/N): "
            read confirm_ma
            case "$confirm_ma" in
                [Yy]*) # Continúa si la respuesta empieza con Y o y
                    ;; 
                *) # Cancela para cualquier otra respuesta
                    echo "\e[33mActualización de Music Assistant cancelada.\e[0m"
                    return 0
                    ;;
            esac
            ;;
    esac

    echo "Descargando la imagen más reciente para ${service_name}..."
    # 'eval' es seguro aquí porque controlamos el contenido de la variable
    if ! eval $DOCKER_COMPOSE_CMD -f "\"${DOCKER_COMPOSE_FILE}\"" pull "\"${service_name}\""; then
        echo "\e[31mERROR:\e[0m No se pudo descargar la nueva imagen para ${service_name}."
        return 1
    fi

    echo "Recreando el contenedor de ${service_name}..."
    if ! eval $DOCKER_COMPOSE_CMD -f "\"${DOCKER_COMPOSE_FILE}\"" up -d --no-deps --force-recreate "\"${service_name}\""; then
        echo "\e[31mERROR:\e[0m No se pudo recrear ${service_name}."
        return 1
    fi

    case "$service_name" in
        homeassistant)
            echo "\e[33mℹ️  Se recomienda ejecutar 'docker restart homeassistant' después de actualizar\e[0m"
            ;;
        music-assistant-server)
            echo "\e[33mℹ️  Verificando permisos para Music Assistant...\e[0m"
            if docker inspect -f '{{.State.Running}}' music-assistant-server >/dev/null 2>&1; then
                docker exec music-assistant-server chown -R root:root /data
            else
                echo "\e[33mAdvertencia: No se pudo ejecutar el post-procesamiento en Music Assistant.\e[0m"
            fi
            ;;
    esac

    echo "$(date +'%F %T') - Servicio actualizado: ${service_name}" >> "${UPDATE_LOG_FILE}"
    echo "=== \e[32m${service_name} actualizado correctamente.\e[0m ==="
    return 0
}

# --- Lógica principal ---

# Detectar si usar 'docker-compose' o 'docker compose' (versión compatible con sh)
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
# Usamos 'docker compose version' para una comprobación más fiable
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="'docker compose'" # Comillas internas para que 'eval' funcione bien
else
    echo "ERROR: No se encontró un comando funcional de Docker Compose." >&2
    exit 1
fi

mkdir -p "$UPDATE_LOG_DIR"
download_compose_file

echo "\n--- GESTOR DE ACTUALIZACIONES MANUALES DE DOCKER COMPOSE ---"

while true; do
    echo "\n--- MENÚ DE ACTUALIZACIÓN ---"
    echo "Selecciona el servicio a actualizar, '0' para todos, o 'q' para salir:"
    echo "  \e[1m0)\e[0m Actualizar TODOS los servicios listados"
    
    # Generar menú sin arrays
    i=1
    for service in $MANUAL_SERVICES; do
        if [ "$service" = "music-assistant-server" ]; then
            echo "  \e[1m$i)\e[0m \e[33m${service} (requisitos especiales)\e[0m"
        else
            echo "  \e[1m$i)\e[0m ${service}"
        fi
        i=$(expr $i + 1)
    done
    SERVICE_COUNT=$(expr $i - 1)

    echo "  \e[1mq)\e[0m Salir"
    printf "Tu elección: "
    read choice

    case "$choice" in
        0)
            printf "¿Estás seguro de que quieres actualizar TODOS los servicios? (y/N): "
            read confirm_all
            case "$confirm_all" in
                [Yy]*)
                    echo "\nIniciando actualizaciones..."
                    for service in $MANUAL_SERVICES; do
                        update_service "$service" || echo "\e[31mFallo al actualizar $service. Continuando...\e[0m"
                    done
                    echo "\n\e[32mTodas las actualizaciones han sido procesadas.\e[0m"
                    break
                    ;;
                *)
                    echo "Actualización cancelada."
                    continue
                    ;;
            esac
            ;;
        [1-9] | [1-9][0-9]) # Acepta números de 1 o 2 dígitos
            if [ "$choice" -gt 0 -a "$choice" -le "$SERVICE_COUNT" ]; then
                # Seleccionar servicio sin arrays, usando 'cut'
                selected_service=$(echo "$MANUAL_SERVICES" | cut -d' ' -f"$choice")
                
                printf "¿Estás seguro de que quieres actualizar ${selected_service}? (y/N): "
                read confirm_single
                case "$confirm_single" in
                    [Yy]*)
                        update_service "$selected_service" || echo "\e[31mFallo al actualizar $selected_service.\e[0m"
                        break
                        ;;
                    *)
                        echo "Actualización cancelada."
                        continue
                        ;;
                esac
            else
                echo "\e[31mERROR:\e[0m Opción inválida."
            fi
            ;;
        [Qq])
            echo "Saliendo del script."
            break
            ;;
        *)
            echo "\e[31mERROR:\e[0m Opción inválida."
            ;;
    esac
done

# --- Limpieza opcional ---
echo "\n--------------------------------------------------"
printf "¿Deseas limpiar imágenes no utilizadas (docker image prune)? (y/N): "
read cleanup_confirm
case "$cleanup_confirm" in
    [Yy]*)
        echo "Ejecutando limpieza..."
        docker image prune -f
        echo "\e[32mLimpieza completada.\e[0m"
        ;;
    *)
        echo "Limpieza omitida."
        ;;
esac

echo "\nScript finalizado.\n"
