#!/bin/bash

# update-mosquitto.sh - Actualización manual de Mosquitto con backup

# 1. Crear backup
BACKUP_DIR="/volume1/docker/mosquitto_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/mosquitto_backup_$TIMESTAMP"

echo "Creando backup de Mosquitto en $BACKUP_PATH"
mkdir -p "$BACKUP_PATH"
cp -r /volume1/docker/mosquitto "$BACKUP_PATH"

# 2. Detener y eliminar contenedor
echo "Deteniendo Mosquitto..."
docker stop mosquitto
docker rm mosquitto

# 3. Actualizar imagen
echo "Actualizando imagen de Mosquitto..."
docker pull eclipse-mosquitto:latest

# 4. Volver a crear contenedor
echo "Reiniciando Mosquitto..."
docker run -d \
  --name mosquitto \
  --restart=always \
  --privileged \
  --network=host \
  -v /volume1/docker/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf \
  -v /volume1/docker/mosquitto/config:/mosquitto/config \
  -v /volume1/docker/mosquitto/data:/mosquitto/data \
  -v /volume1/docker/mosquitto/log:/mosquitto/log \
  -e TZ=America/Mexico_City \
  eclipse-mosquitto:latest

# 5. Monitorear logs
echo "Iniciando monitoreo de logs (Ctrl+C para salir)..."
docker logs -f mosquitto
