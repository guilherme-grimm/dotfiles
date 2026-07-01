#!/bin/bash

# Config
TEMP_LOW=4000    # warm (night) color temp
TEMP_HIGH=6500   # neutral (day) color temp
LAT="-22.4"     # your latitude (SP area)
LON="-46.9"     # your longitude

start_sunset() {
    wlsunset -l $LAT -L $LON -t $TEMP_LOW -T $TEMP_HIGH &
}

case "$1" in
    toggle)
        if pgrep -x wlsunset > /dev/null; then
            pkill wlsunset
        else
            start_sunset
        fi
        ;;
    *)
        # Output JSON for waybar
        if pgrep -x wlsunset > /dev/null; then
            echo '{"text": "󰖔", "tooltip": "Night light ON", "class": "on"}'
        else
            echo '{"text": "󰖕", "tooltip": "Night light OFF", "class": "off"}'
        fi
        ;;
esac
