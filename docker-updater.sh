#!/bin/bash
# Script interactivo para actualizar manualmente servicios Docker Compose específicos.

set -e
set -o pipefail
trap "echo -e '\n\e[31mActualización cancelada. Saliendo del script.\e[0m\n'; exit 1" INT

# --- Variables de configuración ---
DOCKER_COMPOSE_FILE="docker-compose.yml"
UPDATE_LOG_DIR="Updates"
UPDATE_LOG_FILE="${UPDATE_LOG_DIR}/update.log"
MANUAL_SERVICES=("homeassistant" "mosquitto" "zigbee2mqtt" "watchtower" "nodered" "esphome" "codeserver" "music-assistant-server")

# Detectar si usar 'docker-compose' o 'docker compose'
DOCKER_COMPOSE="docker-compose"
command -v docker compose &> /dev/null && DOCKER_COMPOSE="docker compose"

mkdir -p "$UPDATE_LOG_DIR"

# --- Función para actualizar un servicio ---
update_service() {
    local service_name="$1"
    echo -e "\n=== Iniciando actualización para: \e[1m${service_name}\e[0m ==="

    if ! grep -qE "^\s{2}${service_name}:" "$DOCKER_COMPOSE_FILE"; then
        echo -e "\e[31mERROR:\e[0m El servicio '${service_name}' no está definido en ${DOCKER_COMPOSE_FILE}."
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
    if ! ${DOCKER_COMPOSE} -f "${DOCKER_COMPOSE_FILE}" pull "${service_name}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo descargar la nueva imagen para ${service_name}."
        return 1
    fi

    echo "Recreando el contenedor de ${service_name}..."
    if ! ${DOCKER_COMPOSE} -f "${DOCKER_COMPOSE_FILE}" up -d --no-deps --force-recreate "${service_name}"; then
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
            docker exec music-assistant-server chown -R root:root /data
            ;;
    esac

    # Registrar en log
    echo "$(date +'%F %T') - Servicio actualizado: ${service_name}" >> "${UPDATE_LOG_FILE}"
    echo -e "=== \e[32m${service_name} actualizado correctamente.\e[0m ==="
    return 0
}

# --- Menú interactivo ---
echo "--- GESTOR DE ACTUALIZACIONES MANUALES DE DOCKER COMPOSE ---"
echo "Asegúrate de que este script está en el mismo directorio que '${DOCKER_COMPOSE_FILE}'"

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
                if [[ "$service" == "music-assistant-server" ]]; then
                    echo -e "\n\e[33m⚠️  Actualizando Music Assistant (requiere confirmación)...\e[0m"
                    read -p "¿Continuar con la actualización de Music Assistant? (y/N): " confirm_ma
                    if [[ ! "$confirm_ma" =~ ^[Yy]$ ]]; then
                        echo -e "\e[33mActualización de Music Assistant omitida.\e[0m"
                        continue
                    fi
                fi
                update_service "$service" || echo -e "\e[31mFallo al actualizar $service. Continuando...\e[0m"
            done
            echo -e "\n\e[32mTodas las actualizaciones han sido procesadas.\e[0m"
            break
            ;;
        [1-9]*)
            if (( choice >= 1 && choice <= ${#MANUAL_SERVICES[@]} )); then
                selected_service="${MANUAL_SERVICES[choice-1]}"
                echo -e "\e[33mSeleccionaste actualizar: ${selected_service}\e[0m"
                read -p "¿Estás seguro? (y/N): " confirm_single
                if [[ ! "$confirm_single" =~ ^[Yy]$ ]]; then
                    echo "Actualización cancelada."
                    continue
                fi
                update_service "$selected_service" || echo -e "\e[31mFallo al actualizar $selected_service.\e[0m"
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
