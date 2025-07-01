#!/bin/sh
# Actualizador simplificado de contenedores Docker para Synology NAS
# Versión 2.0 - Compatible con ash/sh

# --- Configuración ---
COMPOSE_FILE="/volume1/docker/docker-compose.yml"
SERVICES="homeassistant mosquitto zigbee2mqtt nodered esphome"

# --- Verificar dependencias ---
if ! command -v docker >/dev/null; then
    echo "ERROR: Docker no está instalado" >&2
    exit 1
fi

# --- Función de actualización ---
update_container() {
    service=$1
    echo "=== Actualizando $service ==="
    
    # Pull de la imagen más reciente
    if ! docker compose -f "$COMPOSE_FILE" pull "$service"; then
        echo "ERROR: Falló al descargar $service" >&2
        return 1
    fi
    
    # Reiniciar el contenedor
    if ! docker compose -f "$COMPOSE_FILE" up -d --force-recreate "$service"; then
        echo "ERROR: Falló al reiniciar $service" >&2
        return 1
    fi
    
    echo "✔ $service actualizado correctamente"
    return 0
}

# --- Menú principal ---
while true; do
    echo ""
    echo "=== MENÚ DE ACTUALIZACIÓN ==="
    echo "1) Actualizar todos los servicios"
    i=2
    for service in $SERVICES; do
        echo "$i) Actualizar $service"
        i=$((i+1))
    done
    echo "q) Salir"
    echo ""
    printf "Seleccione una opción: "
    read choice
    
    case $choice in
        1)
            echo "Actualizando TODOS los servicios..."
            for service in $SERVICES; do
                update_container "$service"
            done
            ;;
        [2-9])
            index=$((choice-1))
            service=$(echo $SERVICES | cut -d' ' -f$index)
            if [ -n "$service" ]; then
                update_container "$service"
            else
                echo "Opción inválida"
            fi
            ;;
        q|Q)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción no válida"
            ;;
    esac
done
