#!/bin/bash

VPN_NAME="vpn"

# Check if the WireGuard interface is up (no root needed: /sys/class/net)
is_vpn_active() {
    [ -d "/sys/class/net/$VPN_NAME" ]
}

# Emit JSON for waybar: {text, class, tooltip}. class drives #custom-vpn.connected.
get_vpn_status() {
    if is_vpn_active; then
        echo '{"text": "󰖂 VPN", "class": "connected", "tooltip": "VPN: connected"}'
    else
        echo '{"text": "󰖑 VPN", "class": "disconnected", "tooltip": "VPN: disconnected"}'
    fi
}

# Toggle VPN connection
toggle_vpn() {
    if is_vpn_active; then
        if sudo wg-quick down "$VPN_NAME" 2>/dev/null; then
            notify-send -u normal "VPN Disconnected" "WireGuard interface down"
        else
            notify-send -u critical "VPN Error" "Failed to disconnect"
        fi
    else
        if sudo wg-quick up "$VPN_NAME" 2>/dev/null; then
            notify-send -u normal "VPN Connected" "WireGuard interface up"
        else
            notify-send -u critical "VPN Error" "Failed to connect"
        fi
    fi
}

case "$1" in
    --toggle)
        toggle_vpn
        ;;
    *)
        get_vpn_status
        ;;
esac