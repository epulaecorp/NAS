#!/bin/sh
# Actualizador de contenedores Docker para Synology - Versión minimalista

# Contenedores a actualizar
SERVICES="homeassistant mosquitto zigbee2mqtt nodered esphome"

# Función básica de actualización
update_container() {
    echo "=== Actualizando $1 ==="
    docker pull "$1" && docker-compose up -d --force-recreate "$1"
    echo ""
}

# Menú simple
while true; do
    echo "=== MENÚ ==="
    echo "1) Actualizar TODOS"
    i=2
    for service in $SERVICES; do
        echo "$i) $service"
        i=$((i+1))
    done
    echo "q) Salir"
    echo ""
    printf "Opción: "
    read opcion

    case $opcion in
        1) 
            for service in $SERVICES; do
                update_container "$service"
            done
            ;;
        2) update_container "homeassistant" ;;
        3) update_container "mosquitto" ;;
        4) update_container "zigbee2mqtt" ;;
        5) update_container "nodered" ;;
        6) update_container "esphome" ;;
        q) exit ;;
        *) echo "Opción inválida" ;;
    esac
done
