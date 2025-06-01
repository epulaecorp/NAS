#!/bin/bash
# Script interactivo para actualizar manualmente servicios Docker Compose especificos.

# Configuracion para manejar errores y limpieza
set -e
set -o pipefail
trap "echo -e '\n\e[31mActualizacion cancelada. Saliendo del script.\e[0m\n'; exit 1" INT

# --- Variables de configuracion ---
DOCKER_COMPOSE_FILE="docker-compose2.yml"
MANUAL_SERVICES=("homeassistant" "mosquitto" "zigbee2mqtt" "watchtower" "nodered" "esphome" "code-server")

# --- Funcion para actualizar un servicio Docker Compose ---
update_service() {
    local service_name="$1"
    echo -e "\n=== Iniciando actualizacion para: \e[1m${service_name}\e[0m ==="

    echo "Descargando la imagen mas reciente para ${service_name}..."
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" pull "${service_name}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo descargar la nueva imagen para ${service_name}."
        return 1
    fi

    echo "Recreando el contenedor de ${service_name}..."
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d --no-deps --force-recreate "${service_name}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo recrear ${service_name}. Revisa los logs de Docker."
        return 1
    fi

    echo -e "=== \e[32m${service_name} actualizado correctamente.\e[0m ==="
    return 0
}

# --- Script principal ---
echo "--- GESTOR DE ACTUALIZACIONES MANUALES DE DOCKER COMPOSE ---"
echo "Asegurate de que este script esta en el mismo directorio que '${DOCKER_COMPOSE_FILE}'."

while true; do
    echo -e "\n--- MENU DE ACTUALIZACION ---"
    echo "Selecciona el servicio a actualizar, '0' para todos, o 'q' para salir:"
    echo -e "  \e[1m0)\e[0m Actualizar TODOS los servicios listados"
    for i in "${!MANUAL_SERVICES[@]}"; do
        echo -e "  \e[1m$((i+1)))\e[0m ${MANUAL_SERVICES[i]}"
    done
    echo -e "  \e[1mq)\e[0m Salir"
    echo -n "Tu eleccion: "
    read choice

    case "$choice" in
        0)
            echo -e "\e[33mSeleccionaste actualizar TODOS los servicios.\e[0m"
            read -p "Estas seguro? (y/N): " confirm_all
            if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
                echo "Actualizacion cancelada."
                continue
            fi
            echo -e "\nIniciando actualizaciones..."
            for service in "${MANUAL_SERVICES[@]}"; do
                update_service "$service" || echo -e "\e[31mFallo al actualizar $service. Continuando...\e[0m"
            done
            echo -e "\n\e[32mTodas las actualizaciones han sido procesadas.\e[0m"
            break
            ;;
        [1-9]*[0-9]* | [1-9])
            if (( choice >= 1 && choice <= ${#MANUAL_SERVICES[@]} )); then
                selected_service="${MANUAL_SERVICES[choice-1]}"
                echo -e "\e[33mSeleccionaste actualizar: ${selected_service}\e[0m"
                read -p "Estas seguro? (y/N): " confirm_single
                if [[ ! "$confirm_single" =~ ^[Yy]$ ]]; then
                    echo "Actualizacion cancelada."
                    continue
                fi
                update_service "$selected_service" || echo -e "\e[31mFallo al actualizar $selected_service.\e[0m"
                break
            else
                echo -e "\e[31mERROR:\e[0m Opcion invalida."
            fi
            ;;
        [Qq])
            echo "Saliendo del script."
            break
            ;;
        *)
            echo -e "\e[31mERROR:\e[0m Opcion invalida."
            ;;
    esac
done

# --- Limpieza post-actualizacion ---
echo -e "\n--------------------------------------------------"
read -p "Deseas limpiar imagenes y volumenes no utilizados (docker system prune)? (y/N): " cleanup_confirm
if [[ "$cleanup_confirm" =~ ^[Yy]$ ]]; then
    echo "Ejecutando limpieza..."
    docker system prune -f
    echo -e "\e[32mLimpieza completada.\e[0m"
else
    echo "Limpieza omitida."
fi

echo -e "\nScript finalizado.\n"
