#!/bin/bash

echo "=== Test kontroli monitora ==="

echo "Sprawdzam stan HDMI..."
vcgencmd display_power -1

echo "Wyłączam ekran na 3s..."
vcgencmd display_power 0
sleep 5

echo "Włączam ekran..."
vcgencmd display_power 1
sleep 2

vcgencmd display_power -1

echo "Test zakończony"
