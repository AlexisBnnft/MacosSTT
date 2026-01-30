#!/bin/bash
# Toggle WillowIndicator on/off

if pgrep -x "WillowIndicator" > /dev/null; then
    pkill -x "WillowIndicator"
else
    cd "$(dirname "$0")"
    ./.build/release/WillowIndicator &
fi
