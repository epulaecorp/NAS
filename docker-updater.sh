#!/bin/bash
# Script interactivo para actualizar manualmente servicios Docker Compose específicos.
# Versión 2: Corregido el manejo de 'docker compose' y con descarga automática del archivo de compose.

# --- Configuración de seguridad y manejo de errores ---
set -e
set -o pipefail
trap "echo -e '\n\e[31mActualización cancelada. Saliendo del script.\e[0m\n'; exit 1" INT

# --- Variables de configuración ---

# !! IMPORTANTE: CONFIGURA ESTA URL !!
# Debe ser la URL "raw" (cruda) a tu archivo docker-compose.yml en GitHub, GitLab, etc.
# Ejemplo de GitHub: Ve a tu archivo y haz clic en el botón "Raw". Copia esa URL.
DOCKER_COMPOSE_RAW_URL="https://raw.githubusercontent.com/epulaecorp/NAS/refs/heads/main/docker-compose.yml"

DOCKER_COMPOSE_FILE="docker-compose.yml"
UPDATE_LOG_DIR="Updates"
UPDATE_LOG_FILE="${UPDATE_LOG_DIR}/update.log"
MANUAL_SERVICES=("homeassistant" "mosquitto" "zigbee2mqtt" "watchtower" "nodered" "esphome" "codeserver" "music-assistant-server")

# --- Comprobaciones de Prerrequisitos ---
if ! command -v curl &> /dev/null; then
    echo -e "\e[31mERROR:\e[0m El comando 'curl' es necesario para descargar el archivo de configuración y no está instalado."
    exit 1
fi
if ! command -v docker &> /dev/null; then
    echo -e "\e[31mERROR:\e[0m Docker no está instalado o no se encuentra en el PATH."
    exit 1
fi

# --- Funciones ---

# Función para descargar el archivo docker-compose.yml
download_compose_file() {
    echo "--- Descargando la última versión de '${DOCKER_COMPOSE_FILE}' desde el repositorio ---"
    # Usamos curl con -sSf:
    # -s: Modo silencioso
    # -S: Muestra errores si los hay (a pesar del modo silencioso)
    # -f: Falla silenciosamente en errores HTTP (devuelve código de error para que set -e lo capture)
    # -o: Archivo de salida
    if ! curl -sSf -o "${DOCKER_COMPOSE_FILE}" "${DOCKER_COMPOSE_RAW_URL}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo descargar el archivo desde '${DOCKER_COMPOSE_RAW_URL}'."
        echo "Por favor, verifica la URL y tu conexión a internet."
        exit 1
    fi
    echo -e "\e[32mArchivo '${DOCKER_COMPOSE_FILE}' descargado/actualizado correctamente.\e[0m"
}

# Función para actualizar un servicio
update_service() {
    local service_name="$1"
    echo -e "\n=== Iniciando actualización para: \e[1m${service_name}\e[0m ==="

    if ! grep -qE "^\s{2,}${service_name}:" "$DOCKER_COMPOSE_FILE"; then
        echo -e "\e[31mERROR:\e[0m El servicio '${service_name}' no está definido en el archivo descargado ${DOCKER_COMPOSE_FILE}."
        return 1
    fi

    if [[ "$service_name" == "music-assistant-server" ]]; then
        echo -e "\e[33m⚠️  Advertencia: Music Assistant requiere configuración especial de red y permisos\e[0m"
        read -p "¿Continuar con la actualización? (y/N): " confirm_ma
        if [[ ! "$confirm_ma" =~ ^[Yy]$ ]]; then
            echo -e "\e[33mActualización de Music Assistant cancelada.\e[0m"
            return 0
        fi
    fi

    echo "Descargando la imagen más reciente para ${service_name}..."
    if ! "${DOCKER_COMPOSE_CMD[@]}" -f "${DOCKER_COMPOSE_FILE}" pull "${service_name}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo descargar la nueva imagen para ${service_name}."
        return 1
    fi

    echo "Recreando el contenedor de ${service_name}..."
    if ! "${DOCKER_COMPOSE_CMD[@]}" -f "${DOCKER_COMPOSE_FILE}" up -d --no-deps --force-recreate "${service_name}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo recrear ${service_name}."
        return 1
    fi

    # Post-procesamiento especial
    case "$service_name" in
        homeassistant)
            echo -e "\e[33mℹ️  Se recomienda ejecutar 'docker restart homeassistant' después de actualizar\e[0m"
            ;;
        music-assistant-server)
            echo -e "\e[33mℹ️  Verificando permisos para Music Assistant...\e[0m"
            # Añadimos un chequeo para no fallar si el contenedor no está corriendo
            if docker inspect -f '{{.State.Running}}' music-assistant-server &>/dev/null; then
                docker exec music-assistant-server chown -R root:root /data
            else
                echo -e "\e[33mAdvertencia: No se pudo ejecutar el post-procesamiento en Music Assistant porque el contenedor no está corriendo.\e[0m"
            fi
            ;;
    esac

    # Registrar en log
    echo "$(date +'%F %T') - Servicio actualizado: ${service_name}" >> "${UPDATE_LOG_FILE}"
    echo -e "=== \e[32m${service_name} actualizado correctamente.\e[0m ==="
    return 0
}


# --- Lógica principal ---

# Detectar si usar 'docker-compose' o 'docker compose' (usando un array para seguridad)
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE_CMD=("docker" "compose")
else
    DOCKER_COMPOSE_CMD=("docker-compose")
fi

mkdir -p "$UPDATE_LOG_DIR"

# Descargar el archivo de compose
download_compose_file

echo -e "\n--- GESTOR DE ACTUALIZACIONES MANUALES DE DOCKER COMPOSE ---"

while true; do
    echo -e "\n--- MENÚ DE ACTUALIZACIÓN ---"
    echo "Selecciona el servicio a actualizar, '0' para todos, o 'q' para salir:"
    echo -e "  \e[1m0)\e[0m Actualizar TODOS los servicios listados"
    for i in "${!MANUAL_SERVICES[@]}"; do
        if [[ "${MANUAL_SERVICES[i]}" == "music-assistant-server" ]]; then
            echo -e "  \e[1m$((i+1)))\e[0m \e[33m${MANUAL_SERVICES[i]} (requisitos especiales)\e[0m"
        else
            echo -e "  \e[1m$((i+1)))\e[0m ${MANUAL_SERVICES[i]}"
        fi
    done
    echo -e "  \e[1mq)\e[0m Salir"
    echo -n "Tu elección: "
    read choice

    case "$choice" in
        0)
            echo -e "\e[33mSeleccionaste actualizar TODOS los servicios.\e[0m"
            read -p "¿Estás seguro? Esto incluye servicios con requisitos especiales. (y/N): " confirm_all
            if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
                echo "Actualización cancelada."
                continue
            fi
            echo -e "\nIniciando actualizaciones..."
            for service in "${MANUAL_SERVICES[@]}"; do
                update_service "$service" || echo -e "\e[31mFallo al actualizar $service. Continuando...\e[0m"
            done
            echo -e "\n\e[32mTodas las actualizaciones han sido procesadas.\e[0m"
            # Salimos del bucle while después de actualizar todos
            break
            ;;
        [1-9]*)
            if (( choice > 0 && choice <= ${#MANUAL_SERVICES[@]} )); then
                selected_service="${MANUAL_SERVICES[choice-1]}"
                echo -e "\e[33mSeleccionaste actualizar: ${selected_service}\e[0m"
                read -p "¿Estás seguro? (y/N): " confirm_single
                if [[ ! "$confirm_single" =~ ^[Yy]$ ]]; then
                    echo "Actualización cancelada."
                    continue
                fi
                update_service "$selected_service" || echo -e "\e[31mFallo al actualizar $selected_service.\e[0m"
                # Salimos del bucle while después de una actualización exitosa o fallida
                break
            else
                echo -e "\e[31mERROR:\e[0m Opción inválida."
            fi
            ;;
        [Qq])
            echo "Saliendo del script."
            break
            ;;
        *)
            echo -e "\e[31mERROR:\e[0m Opción inválida."
            ;;
    esac
done

# --- Limpieza opcional ---
echo -e "\n--------------------------------------------------"
read -p "¿Deseas limpiar imágenes y volúmenes no utilizados (docker system prune)? (y/N): " cleanup_confirm
if [[ "$cleanup_confirm" =~ ^[Yy]$ ]]; then
    echo "Ejecutando limpieza..."
    docker system prune -f
    echo -e "\e[32mLimpieza completada.\e[0m"
else
    echo "Limpieza omitida."
fi

echo -e "\nScript finalizado.\n"
