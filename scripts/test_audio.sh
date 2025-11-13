#!/bin/bash

# Test mikrofonu i głośnika (ALSA)
arecord -l
aplay -l

echo "Nagraj 3s dźwięk (wybierz urządzenie jeśli potrzeba)..."
arecord -d 3 test.wav
aplay test.wav

echo "Test audio zakończony"
