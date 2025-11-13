#!/bin/bash

###############################################################################
# RPi HA Wall Panel - Automatyczny instalator
# Autor: Pablohass
# Wersja: 1.0.0
###############################################################################

set -e  # Exit on error

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logo
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🏠 RPi Home Assistant Wall Panel                     ║
║        + Voice Assistant Installer                       ║
║                                                           ║
║     Version: 1.0.0                                        ║
║     Author: @Pablohass                                    ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Sprawdź czy jesteśmy na RPi
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    echo -e "${RED}❌ Ten skrypt działa tylko na Raspberry Pi!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Wykryto Raspberry Pi${NC}"

# Wczytaj konfigurację
if [ ! -f "config.env" ]; then
    echo -e "${YELLOW}⚠️  Nie znaleziono config.env, tworzę z szablonu...${NC}"
    cat > config.env << 'EOF'
# Home Assistant Configuration
HA_URL="http://192.168.1.100:8123"
HA_TOKEN=""  # Opcjonalne, dla API calls

# MQTT Configuration
MQTT_BROKER="192.168.1.100"
MQTT_PORT=1883
MQTT_USER="mqtt_user"
MQTT_PASSWORD="mqtt_password"

# Display Configuration
DISPLAY_NAME="Monitor HA"
KIOSK_URL="${HA_URL}"

# Voice Assistant Configuration
WAKE_WORD="hey_jarvis"
STT_LANGUAGE="pl"
TTS_LANGUAGE="pl_PL"
TTS_VOICE="pl_PL-darkman-medium"

# Audio Configuration (zostaw puste dla auto-detect)
MICROPHONE_DEVICE=""
SPEAKER_DEVICE=""

# WiFi Configuration (opcjonalne, jeśli używasz WiFi zamiast LAN)
WIFI_SSID=""
WIFI_PASSWORD=""

# Timezone
TIMEZONE="Europe/Warsaw"
EOF
    echo -e "${YELLOW}📝 Edytuj config.env i uruchom ponownie:${NC}"
    echo -e "${YELLOW}   nano config.env${NC}"
    echo -e "${YELLOW}   ./install.sh${NC}"
    exit 0
fi

# Wczytaj zmienne
source config.env

echo -e "${BLUE}📋 Konfiguracja:${NC}"
echo -e "   HA URL: ${HA_URL}"
echo -e "   MQTT Broker: ${MQTT_BROKER}:${MQTT_PORT}"
echo -e "   MQTT User: ${MQTT_USER}"
echo -e "   Wake Word: ${WAKE_WORD}"
echo -e "   Language: ${STT_LANGUAGE}"
echo -e ""

read -p "Czy kontynuować instalację? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Instalacja anulowana${NC}"
    exit 1
fi

###############################################################################
# KROK 1: Update systemu
###############################################################################
echo -e "\n${BLUE}[1/10]${NC} Aktualizacja systemu..."
sudo apt update
sudo apt upgrade -y

###############################################################################
# KROK 2: Instalacja GUI (minimal)
###############################################################################
echo -e "\n${BLUE}[2/10]${NC} Instalacja GUI (Openbox + Chromium)..."
sudo apt install --no-install-recommends -y \
    xorg \
    xserver-xorg-video-fbdev \
    openbox \
    lightdm \
    chromium-browser \
    unclutter \
    xinput \
    xdotool \
    x11-xserver-utils

###############################################################################
# KROK 3: Instalacja audio
###############################################################################
echo -e "\n${BLUE}[3/10]${NC} Instalacja audio (ALSA + PulseAudio)..."
sudo apt install -y \
    alsa-utils \
    pulseaudio \
    pulseaudio-utils

###############################################################################
# KROK 4: Instalacja Python dependencies
###############################################################################
echo -e "\n${BLUE}[4/10]${NC} Instalacja Python + dependencies..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-flask \
    python3-paho-mqtt

###############################################################################
# KROK 5: Instalacja DDC/CI (kontrola monitora)
###############################################################################
echo -e "\n${BLUE}[5/10]${NC} Instalacja ddcutil (DDC/CI)..."
sudo apt install -y ddcutil i2c-tools

# Dodaj użytkownika do grupy i2c
sudo usermod -a -G i2c $USER

# Enable I2C
if ! grep -q "^dtparam=i2c_arm=on" /boot/config.txt; then
    echo "dtparam=i2c_arm=on" | sudo tee -a /boot/config.txt
fi

###############################################################################
# KROK 6: Instalacja Wyoming Satellite (Voice Assistant)
###############################################################################
echo -e "\n${BLUE}[6/10]${NC} Instalacja Wyoming Satellite..."

# Instaluj zależności
sudo apt install -y \
    git \
    python3-dev \
    build-essential \
    portaudio19-dev \
    libopenblas-dev

# Klonuj Wyoming Satellite
if [ ! -d "$HOME/wyoming-satellite" ]; then
    cd $HOME
    git clone https://github.com/rhasspy/wyoming-satellite.git
    cd wyoming-satellite
else
    cd $HOME/wyoming-satellite
    git pull
fi

# Utwórz venv i zainstaluj
python3 -m venv venv
source venv/bin/activate
pip3 install --upgrade pip wheel setuptools
pip3 install -r requirements.txt
pip3 install wyoming openwakeword wyoming-openwakeword
deactivate

echo -e "${GREEN}✅ Wyoming Satellite zainstalowany${NC}"

###############################################################################
# KROK 7: Instalacja Bluetooth (opcjonalnie)
###############################################################################
echo -e "\n${BLUE}[7/10]${NC} Instalacja Bluetooth..."
sudo apt install -y bluetooth bluez bluez-tools

###############################################################################
# KROK 8: Konfiguracja auto-login
###############################################################################
echo -e "\n${BLUE}[8/10]${NC} Konfiguracja auto-login..."
sudo raspi-config nonint do_boot_behaviour B2

###############################################################################
# KROK 9: Konfiguracja plików
###############################################################################
echo -e "\n${BLUE}[9/10]${NC} Kopiowanie plików konfiguracyjnych..."

# Openbox autostart
mkdir -p ~/.config/openbox
cp config/openbox/autostart ~/.config/openbox/autostart
chmod +x ~/.config/openbox/autostart

# Zastąp zmienne w autostart
sed -i "s|{{HA_URL}}|${KIOSK_URL}|g" ~/.config/openbox/autostart

# ALSA config
cp config/alsa/.asoundrc ~/.asoundrc

# HDMI control script
mkdir -p ~/ha-display
cp scripts/hdmi_control.py ~/ha-display/

# Zastąp zmienne w hdmi_control.py
sed -i "s|{{MQTT_BROKER}}|${MQTT_BROKER}|g" ~/ha-display/hdmi_control.py
sed -i "s|{{MQTT_PORT}}|${MQTT_PORT}|g" ~/ha-display/hdmi_control.py
sed -i "s|{{MQTT_USER}}|${MQTT_USER}|g" ~/ha-display/hdmi_control.py
sed -i "s|{{MQTT_PASSWORD}}|${MQTT_PASSWORD}|g" ~/ha-display/hdmi_control.py
sed -i "s|{{DISPLAY_NAME}}|${DISPLAY_NAME}|g" ~/ha-display/hdmi_control.py
sed -i "s|{{HA_URL}}|${HA_URL}|g" ~/ha-display/hdmi_control.py

# Test scripts
cp scripts/test_*.sh ~/ha-display/
chmod +x ~/ha-display/test_*.sh

# Systemd services
sudo cp config/systemd/hdmi-control.service /etc/systemd/system/
sudo cp config/systemd/wyoming-satellite.service /etc/systemd/system/

# Zastąp ścieżki w service files
sudo sed -i "s|/home/pi|$HOME|g" /etc/systemd/system/hdmi-control.service
sudo sed -i "s|/home/pi|$HOME|g" /etc/systemd/system/wyoming-satellite.service

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable hdmi-control.service
sudo systemctl enable wyoming-satellite.service

###############################################################################
# KROK 10: Finalizacja
###############################################################################
echo -e "\n${BLUE}[10/10]${NC} Finalizacja..."

# Set timezone
sudo timedatectl set-timezone ${TIMEZONE}

# Disable screen blanking
if ! grep -q "^xserver-command=X -s 0 -dpms" /etc/lightdm/lightdm.conf; then
    echo "xserver-command=X -s 0 -dpms" | sudo tee -a /etc/lightdm/lightdm.conf
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║              ✅ Instalacja zakończona!                    ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Następne kroki:${NC}"
echo ""
echo -e "1. ${BLUE}Podłącz hardware:${NC}"
echo -e "   - Mini HDMI → Monitor"
echo -e "   - USB-C (monitor touch) → RPi USB-A"
echo -e "   - USB Audio → RPi USB-A"
echo ""
echo -e "2. ${BLUE}Restart RPi:${NC}"
echo -e "   ${YELLOW}sudo reboot${NC}"
echo ""
echo -e "3. ${BLUE}Po restarcie sprawdź:${NC}"
echo -e "   - Monitor powinien pokazać HA dashboard"
echo -e "   - W HA: Settings → Devices → 'RPi Wall Panel'"
echo ""
echo -e "4. ${BLUE}Test asystenta głosowego:${NC}"
echo -e "   Powiedz: '${WAKE_WORD}' przy RPi"
echo ""
echo -e "5. ${BLUE}Test kontroli monitora:${NC}"
echo -e "   W HA: switch.turn_off switch.monitor_ha"
echo ""
echo -e "${GREEN}📚 Dokumentacja: ~/rpi-ha-wall-panel/docs/${NC}"
echo -e "${GREEN}🛠️  Testy: ~/ha-display/test_*.sh${NC}"
echo ""

read -p "Restart teraz? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Restartuję...${NC}"
    sudo reboot
fi
