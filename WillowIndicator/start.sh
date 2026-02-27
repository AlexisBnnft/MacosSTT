#!/bin/bash
# Start Willow - Push-to-talk transcription with notch indicator

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Starting Willow..."

# Start the Swift indicator in background
"$SCRIPT_DIR/.build/release/WillowIndicator" &
INDICATOR_PID=$!

# Give it a moment to start
sleep 0.5

# Start the Python app
python3 "$SCRIPT_DIR/willow.py"

# When Python exits, kill the indicator
kill $INDICATOR_PID 2>/dev/null
