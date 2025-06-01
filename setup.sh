#!/bin/bash

# ============================================================================
# Script de instalación para stack domótico en Docker (Home Assistant, ESPHome,
# Node-RED, Mosquitto, Zigbee2MQTT y VSCode)
# Autor: epulaecorp
# Repositorio: https://github.com/epulaecorp/NAS
# Fecha: 2025-06-01
# ============================================================================
# ============================================================================
# cd /volume1/docker
# wget https://raw.githubusercontent.com/epulaecorp/NAS/main/domotica-setup.sh
# chmod +x domotica-setup.sh
# ./domotica-setup.sh
# ============================================================================

set -e  # Detener script ante errores

echo "📦 Creando directorios necesarios..."
mkdir -p /volume1/docker/{homeassistant,esphome/config,nodered/data,mosquitto/{config,data,log},vcode,zigbee2mqtt/data,Updates}

echo "📥 Descargando archivos base de configuración..."
cd /volume1/docker
wget -nc https://raw.githubusercontent.com/epulaecorp/NAS/main/docker-compose.yml
wget -nc https://raw.githubusercontent.com/epulaecorp/NAS/main/docker-updater.sh
chmod +x docker-updater.sh

echo "📥 Descargando configuración de Mosquitto..."
cd /volume1/docker/mosquitto/config
wget -nc https://raw.githubusercontent.com/epulaecorp/NAS/main/mosquitto/mosquitto.conf
wget -nc https://raw.githubusercontent.com/epulaecorp/NAS/main/mosquitto/pwfile

echo "🔒 Ajustando permisos..."
chmod -R 775 /volume1/docker

echo "🚀 Iniciando servicios con Docker Compose..."
cd /volume1/docker
docker-compose up -d

echo "🔁 Reemplazando configuración personalizada de Zigbee2MQTT..."
cd /volume1/docker/zigbee2mqtt/data
rm -f configuration.yaml
wget -nc https://raw.githubusercontent.com/epulaecorp/NAS/main/zigbee2mqtt/data/configuration.yaml

echo "🔁 Reemplazando configuración personalizada de Node-RED..."
cd /volume1/docker/nodered/data
rm -f settings.js
wget -nc https://raw.githubusercontent.com/epulaecorp/NAS/main/nodered/data/settings.js

chmod -R 775 /volume1/docker

echo "🔧 Instalando HACS en Home Assistant..."
docker exec homeassistant bash -c "wget -O - https://get.hacs.xyz | bash"
docker restart homeassistant

echo "🎨 Instalando tema en Node-RED..."
docker exec nodered bash -c "npm install @node-red-contrib-themes/theme-collection"
docker restart nodered

echo "✅ Reiniciando Mosquitto..."
docker restart mosquitto

echo "✅ Instalación completa. Revisa los contenedores con 'docker ps'."
