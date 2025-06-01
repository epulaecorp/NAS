#!/bin/bash

# update-zigbee2mqtt.sh - Actualización manual de Zigbee2MQTT con backup

# 1. Crear backup
BACKUP_DIR="/volume1/docker/zigbee2mqtt_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/zigbee2mqtt_backup_$TIMESTAMP"

echo "Creando backup de Zigbee2MQTT en $BACKUP_PATH"
mkdir -p "$BACKUP_PATH"
cp -r /volume1/docker/zigbee2mqtt "$BACKUP_PATH"

# 2. Detener y eliminar contenedor
echo "Deteniendo Zigbee2MQTT..."
docker stop zigbee2mqtt
docker rm zigbee2mqtt

# 3. Actualizar imagen
echo "Actualizando imagen de Zigbee2MQTT..."
docker pull koenkk/zigbee2mqtt:latest

# 4. Volver a crear contenedor
echo "Reiniciando Zigbee2MQTT..."
docker run -d \
  --name zigbee2mqtt \
  --restart=always \
  --privileged \
  --network=host \
  -v /volume1/docker/zigbee2mqtt/data:/app/data \
  -v /run/udev:/run/udev:ro \
  -e TZ=America/Mexico_City \
  koenkk/zigbee2mqtt:latest

# 5. Monitorear logs
echo "Iniciando monitoreo de logs (Ctrl+C para salir)..."
docker logs -f zigbee2mqtt
