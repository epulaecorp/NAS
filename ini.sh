# Define la URL base para no repetirla
BASE_URL="https://raw.githubusercontent.com/epulaecorp/NAS/main"

echo "Iniciando descarga y sobrescritura de archivos..."

# Descarga cada archivo, forzando la sobrescritura con la opción -O
wget -O docker-compose.yml "${BASE_URL}/docker-compose.yml"
wget -O docker-updater.sh "${BASE_URL}/docker-updater.sh"
wget -O setup.sh "${BASE_URL}/setup.sh"

echo "Archivos actualizados correctamente."
