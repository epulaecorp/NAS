#!/bin/bash
# Script interactivo para actualizar manualmente servicios Docker Compose específicos.

# Configuración para manejar errores y limpieza
set -e                # Sale inmediatamente si un comando falla
set -o pipefail       # Si algún comando en un pipeline falla, el pipeline falla
trap "echo -e '\n\e[31m¡Actualización cancelada! Saliendo del script.\e[0m\n'; exit 1" INT # Captura Ctrl+C

# --- Variables de configuración ---
DOCKER_COMPOSE_FILE="docker-compose2.yml" # Nombre del archivo docker-compose.yml
# Lista de servicios a actualizar manualmente.
# Estos son los que NO tienen la etiqueta Watchtower, más Watchtower mismo (para control manual).
MANUAL_SERVICES=("homeassistant" "mosquitto" "zigbee2mqtt" "watchtower" "nodered" "esphome" "code-server")

# --- Función para actualizar un servicio Docker Compose ---
update_service() {
    local service_name="$1"
    echo -e "\n=== Iniciando actualización para: \e[1m${service_name}\e[0m ==="

    echo "Descargando la imagen más reciente para ${service_name}..."
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" pull "${service_name}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo descargar la nueva imagen para ${service_name}. Revise su conexión o el nombre de la imagen."
        return 1
    fi

    echo "Recreando el contenedor de ${service_name} con la nueva imagen (detiene, elimina y crea nuevo)..."
    # --no-deps: No inicia las dependencias del servicio (si las hubiera).
    # --force-recreate: Siempre recrea el contenedor, incluso si no hay cambios en la configuración.
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d --no-deps --force-recreate "${service_name}"; then
        echo -e "\e[31mERROR:\e[0m No se pudo recrear ${service_name} con la nueva imagen. Revise los logs de Docker y su archivo docker-compose.yml."
        return 1
    fi

    echo -e "=== \e[32m${service_name} actualizado correctamente.\e[0m ==="
    return 0
}

# --- Script principal ---

echo "--- GESTOR DE ACTUALIZACIONES MANUALES DE DOCKER COMPOSE ---"
echo "Asegúrate de que este script está en el mismo directorio que tu '${DOCKER_COMPOSE_FILE}'."

# --- Bucle del menú interactivo ---
while true; do
    echo -e "\n--- MENÚ DE ACTUALIZACIÓN ---"
    echo "Selecciona el servicio a actualizar, '0' para todos, o 'q' para salir:"
    echo "  \e[1m0)\e[0m Actualizar TODOS los servicios listados"
    for i in "${!MANUAL_SERVICES[@]}"; do
        echo "  \e[1m$((i+1)))\e[0m ${MANUAL_SERVICES[i]}"
    done
    echo "  \e[1mq)\e[0m Salir"
    echo -n "Tu elección: "
    read choice

    case "$choice" in
        0)
            echo -e "\e[33mHas seleccionado actualizar TODOS los servicios manualmente.\e[0m"
            read -p "¿Estás seguro? (y/N): " confirm_all
            if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
                echo "Actualización de todos los servicios cancelada."
                continue
            fi
            echo -e "\nIniciando actualizaciones de todos los servicios..."
            for service in "${MANUAL_SERVICES[@]}"; do
                update_service "$service" || echo -e "\e[31mFallo al actualizar $service, continuando con el siguiente...\e[0m"
            done
            echo -e "\n\e[32mTodas las actualizaciones seleccionadas han sido procesadas.\e[0m"
            break # Salir del bucle después de actualizar todos
            ;;
        [1-9]*[0-9]* | [1-9]) # Para números de uno o más dígitos
            if (( choice >= 1 && choice <= ${#MANUAL_SERVICES[@]} )); then
                selected_service="${MANUAL_SERVICES[choice-1]}"
                echo -e "\e[33mHas seleccionado actualizar: ${selected_service}\e[0m"
                read -p "¿Estás seguro? (y/N): " confirm_single
                if [[ ! "$confirm_single" =~ ^[Yy]$ ]]; then
                    echo "Actualización de ${selected_service} cancelada."
                    continue
                fi
                update_service "$selected_service" || echo -e "\e[31mFallo al actualizar $selected_service.\e[0m"
                # Puedes elegir si quieres salir del script aquí o volver al menú.
                # Para volver al menú: 'continue'
                # Para salir después de una actualización única: 'break' (he puesto 'break' por defecto)
                break
            else
                echo -e "\e[31mERROR:\e[0m Opción inválida. Por favor, ingresa un número de la lista."
            fi
            ;;
        [Qq])
            echo "Saliendo del script de actualización."
            break
            ;;
        *)
            echo -e "\e[31mERROR:\e[0m Opción inválida. Por favor, intenta de nuevo."
            ;;
    esac
done

# --- Limpieza post-actualización (opcional) ---
echo -e "\n--------------------------------------------------"
read -p "¿Deseas limpiar imágenes y volúmenes Docker no utilizados (docker system prune)? Esto puede liberar espacio. (y/N): " cleanup_confirm
if [[ "$cleanup_confirm" =~ ^[Yy]$ ]]; then
    echo "Realizando limpieza de Docker (esto puede tardar unos segundos)..."
    docker system prune -f # '-f' para forzar la eliminación sin preguntar de nuevo
    echo -e "\e[32mLimpieza completada.\e[0m"
else
    echo "Limpieza omitida."
fi

echo -e "\nScript de actualización finalizado.\n"
