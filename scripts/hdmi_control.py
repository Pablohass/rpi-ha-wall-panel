#!/usr/bin/env python3
"""
RPi HA Wall Panel - HDMI Monitor Control with MQTT
Supports: vcgencmd + DDC/CI + screen blanking
"""

import paho.mqtt.client as mqtt
import subprocess
import time
import json
import os
import sys
import logging

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('hdmi-control')

# Configuration (will be replaced by install.sh)
MQTT_BROKER = "{{MQTT_BROKER}}"
MQTT_PORT = {{MQTT_PORT}}
MQTT_USER = "{{MQTT_USER}}"
MQTT_PASSWORD = "{{MQTT_PASSWORD}}"

DISPLAY_NAME = "{{DISPLAY_NAME}}"
HA_URL = "{{HA_URL}}"

MQTT_TOPIC_CMD = "homeassistant/switch/rpi_hdmi/set"
MQTT_TOPIC_STATE = "homeassistant/switch/rpi_hdmi/state"
MQTT_TOPIC_AVAIL = "homeassistant/switch/rpi_hdmi/availability"

DISPLAY = ":0"
DDC_AVAILABLE = False

# Check DDC/CI support
def check_ddc():
    """Check if monitor supports DDC/CI"""
    global DDC_AVAILABLE
    try:
        result = subprocess.run(
            ['ddcutil', 'detect'],
            capture_output=True,
            text=True,
            timeout=5
        )
        DDC_AVAILABLE = 'Display 1' in result.stdout
        if DDC_AVAILABLE:
            logger.info("✅ DDC/CI available - hardware control enabled")
        else:
            logger.info("⚠️  DDC/CI not available - using vcgencmd only")
        return DDC_AVAILABLE
    except Exception as e:
        logger.warning(f"DDC/CI check failed: {e}")
        DDC_AVAILABLE = False
        return False

def get_hdmi_status():
    """Check if HDMI is powered on"""
    try:
        result = subprocess.run(
            ['vcgencmd', 'display_power', '-1'],
            capture_output=True,
            text=True,
            timeout=2
        )
        return 'ON' if '1' in result.stdout else 'OFF'
    except Exception as e:
        logger.error(f"Failed to get HDMI status: {e}")
        return 'UNKNOWN'

def blank_screen():
    """Show black screen before turning off HDMI"""
    try:
        # Method 1: Kill Chromium and show black
        subprocess.run(['pkill', '-f', 'chromium'], stderr=subprocess.DEVNULL)
        time.sleep(0.5)
        
        # Method 2: DPMS standby
        subprocess.run(
            ['xset', 'dpms', 'force', 'standby'],
            env={'DISPLAY': DISPLAY},
            stderr=subprocess.DEVNULL
        )
        
        logger.info("Screen blanked")
    except Exception as e:
        logger.warning(f"Screen blanking failed: {e}")

def restore_display():
    """Restore Home Assistant dashboard"""
    try:
        # Kill any existing Chromium
        subprocess.run(['pkill', '-f', 'chromium'], stderr=subprocess.DEVNULL)
        time.sleep(1)
        
        # Start Chromium in kiosk mode
        subprocess.Popen([
            'chromium-browser',
            '--kiosk',
            '--noerrdialogs',
            '--disable-infobars',
            '--no-first-run',
            '--disable-session-crashed-bubble',
            '--disable-pinch',
            '--overscroll-history-navigation=0',
            HA_URL
        ], env={'DISPLAY': DISPLAY}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        logger.info("Display restored with HA dashboard")
    except Exception as e:
        logger.error(f"Failed to restore display: {e}")


def set_hdmi_power(state):
    """
    Set HDMI power state
    Uses DDC/CI if available, otherwise vcgencmd
    """
    try:
        if state == 'OFF':
            logger.info("Turning off display...")
            
            # Step 1: Blank screen (no blue screen!)
            blank_screen()
            time.sleep(1)
            
            # Step 2: DDC/CI brightness to 0 (if available)
            if DDC_AVAILABLE:
                logger.info("Setting brightness to 0 via DDC/CI")
                subprocess.run(
                    ['ddcutil', 'setvcp', '10', '0'],
                    capture_output=True,
                    timeout=10
                )
                time.sleep(0.5)
            
            # Step 3: Turn off HDMI signal
            subprocess.run(['vcgencmd', 'display_power', '0'])
            logger.info("HDMI signal OFF")
            
            # Monitor will auto-sleep after ~30s
            
        else:  # state == 'ON'
            logger.info("Turning on display...")
            
            # Step 1: Turn on HDMI signal
            subprocess.run(['vcgencmd', 'display_power', '1'])
            logger.info("HDMI signal ON")
            
            # Wait for monitor to wake
            time.sleep(3)
            
            # Step 2: Restore brightness (if DDC available)
            if DDC_AVAILABLE:
                logger.info("Restoring brightness via DDC/CI")
                subprocess.run(
                    ['ddcutil', 'setvcp', '10', '100'],
                    capture_output=True,
                    timeout=10
                )
            
            # Step 3: Restore HA dashboard
            restore_display()
            
        return get_hdmi_status()
        
    except Exception as e:
        logger.error(f"Failed to set HDMI power: {e}")
        return 'UNKNOWN'

# MQTT Callbacks
def on_connect(client, userdata, flags, rc):
    """MQTT connection callback"""
    if rc == 0:
        logger.info(f"✅ Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
        client.subscribe(MQTT_TOPIC_CMD)
        client.publish(MQTT_TOPIC_AVAIL, "online", retain=True)
        
        # Publish initial state
        current_state = get_hdmi_status()
        client.publish(MQTT_TOPIC_STATE, current_state, retain=True)
        logger.info(f"Initial display state: {current_state}")
    else:
        logger.error(f"❌ MQTT connection failed with code: {rc}")

def on_message(client, userdata, msg):
    """MQTT message callback"""
    payload = msg.payload.decode()
    logger.info(f"📨 Received command: {payload}")
    
    if payload in ['ON', 'OFF']:
        new_state = set_hdmi_power(payload)
        client.publish(MQTT_TOPIC_STATE, new_state, retain=True)
        logger.info(f"✅ Display state changed to: {new_state}")
    else:
        logger.warning(f"⚠️  Unknown command: {payload}")

def on_disconnect(client, userdata, rc):
    """MQTT disconnect callback"""
    if rc != 0:
        logger.warning(f"⚠️  Unexpected MQTT disconnection. Reconnecting...")

# Main
def main():
    logger.info("=" * 60)
    logger.info("🏠 RPi HA Wall Panel - HDMI Monitor Control")
    logger.info("=" * 60)
    
    # Check DDC/CI support
    check_ddc()
    
    # Setup MQTT client
    client = mqtt.Client(client_id="rpi_hdmi_pablohass", clean_session=True)
    client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect
    
    # Last Will (offline status)
    client.will_set(MQTT_TOPIC_AVAIL, "offline", retain=True)
    
    # Connect to broker
    logger.info(f"🔌 Connecting to MQTT broker: {MQTT_BROKER}:{MQTT_PORT}")
    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
    except Exception as e:
        logger.error(f"❌ Failed to connect to MQTT broker: {e}")
        logger.error(f"   Please check:")
        logger.error(f"   - MQTT broker is running at {MQTT_BROKER}:{MQTT_PORT}")
        logger.error(f"   - Username/password are correct")
        logger.error(f"   - Network connectivity")
        sys.exit(1)
    
    # Publish Home Assistant MQTT Discovery
    discovery_config = {
        "name": DISPLAY_NAME,
        "unique_id": "rpi_hdmi_monitor_pablohass",
        "command_topic": MQTT_TOPIC_CMD,
        "state_topic": MQTT_TOPIC_STATE,
        "availability_topic": MQTT_TOPIC_AVAIL,
        "payload_on": "ON",
        "payload_off": "OFF",
        "state_on": "ON",
        "state_off": "OFF",
        "optimistic": False,
        "qos": 1,
        "retain": True,
        "icon": "mdi:monitor",
        "device": {
            "identifiers": ["rpi_wall_panel_pablohass"],
            "name": "RPi Wall Panel",
            "model": "Raspberry Pi 4 + 15.6" Touch Display",
            "manufacturer": "Raspberry Pi Foundation",
            "sw_version": "1.0.0"
        }
    }
    
    client.publish(
        "homeassistant/switch/rpi_hdmi/config",
        json.dumps(discovery_config),
        retain=True
    )
    
    logger.info("📢 Published MQTT Discovery config to Home Assistant")
    logger.info("✅ HDMI Monitor Control ready!")
    logger.info("-" * 60)
    
    # Start MQTT loop
    try:
        client.loop_forever()
    except KeyboardInterrupt:
        logger.info("\n👋 Shutting down gracefully...")
        client.publish(MQTT_TOPIC_AVAIL, "offline", retain=True)
        client.disconnect()
        sys.exit(0)

if __name__ == "__main__":
    main()
