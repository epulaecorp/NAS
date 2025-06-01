#!/bin/bash

# update-homeassistant.sh - Actualización manual de Home Assistant con backup

# 1. Crear backup
BACKUP_DIR="/volume1/docker/homeassistant_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/homeassistant_backup_$TIMESTAMP"

echo "Creando backup de Home Assistant en $BACKUP_PATH"
mkdir -p "$BACKUP_DIR"
cp -r /volume1/docker/homeassistant "$BACKUP_PATH"

# 2. Detener y eliminar contenedor
echo "Deteniendo Home Assistant..."
docker stop homeassistant
docker rm homeassistant

# 3. Actualizar imagen
echo "Actualizando imagen de Home Assistant..."
docker pull ghcr.io/home-assistant/home-assistant:stable

# 4. Volver a crear contenedor
echo "Reiniciando Home Assistant..."
docker run -d \
  --name homeassistant \
  --restart=always \
  --privileged \
  --network=host \
  -v /volume1/docker/homeassistant:/config \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/localtime:/etc/localtime:ro \
  -v /run/dbus:/run/dbus:ro \
  home-assistant/home-assistant:stable

# 5. Monitorear logs
echo "Iniciando monitoreo de logs (Ctrl+C para salir)..."
docker logs -f homeassistant
