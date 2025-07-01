sudo rm -f /volume1/docker/*.sh /volume1/docker/docker-compose.yml

sudo mkdir -p /volume1/docker && cd /volume1/docker && sudo wget --no-check-certificate -q https://raw.githubusercontent.com/epulaecorp/NAS/main/{docker-compose.yml,setup.sh,updater.sh} && sudo chmod +x *.sh
