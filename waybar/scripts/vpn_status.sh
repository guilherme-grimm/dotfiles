#!/bin/bash
# VPN waybar module — Tailscale exit nodes, incl. Mullvad add-on servers.
#
# Left click : toggle last exit node (or suggested one) on/off
# Right click: rofi picker over every available exit node
#
# Requires: tailscale set --operator=$USER  (done once, password needed)

CACHE="$HOME/.cache/waybar-vpn-last"

pretty() {
    # "al-tia-wg-001.mullvad.ts.net." -> "al-tia"
    # "srv579289.tailabcd.ts.net."     -> "srv579289"
    sed -E 's/\.(tail[0-9a-z]+|mullvad)\.ts\.net\.?$//; s/^mullvad-//; s/-wg-?[0-9]+$//' <<< "$1"
}

current_exit_node() {
    tailscale status --json 2>/dev/null |
        jq -r '[.Peer[] | select(.ExitNode == true)][0].DNSName // empty'
}

# Emit waybar JSON: {text, class, tooltip}
get_vpn_status() {
    local cur label online
    cur=$(current_exit_node)
    if [[ -n "$cur" ]]; then
        label=$(pretty "$cur")
        online=$(tailscale status --json 2>/dev/null | jq -r '[.Peer[] | select(.ExitNode == true)][0].Online')
        printf '{"text": "󰖂 %s", "class": "connected", "tooltip": "VPN: %s (%s)"}\n' \
            "$label" "$label" "$([ "$online" = "true" ] && echo online || echo offline)"
    else
        echo '{"text": "󰖑 VPN", "class": "disconnected", "tooltip": "VPN: off"}'
    fi
}

set_node() {
    if tailscale set --exit-node="$1" --exit-node-allow-lan-access=true; then
        notify-send -u normal "VPN" "Connected: $(pretty "$1")"
    else
        notify-send -u critical "VPN Error" "Failed to connect to $1"
    fi
}

toggle_vpn() {
    local cur node
    cur=$(current_exit_node)
    if [[ -n "$cur" ]]; then
        printf '%s\n' "$cur" > "$CACHE"
        if tailscale set --exit-node=; then
            notify-send -u normal "VPN" "Disconnected: $(pretty "$cur")"
        else
            notify-send -u critical "VPN Error" "Failed to disconnect"
        fi
    else
        node=$(cat "$CACHE" 2>/dev/null)
        # Fall back to suggested node if the remembered one is gone
        if [[ -z "$node" ]] || ! tailscale exit-node list 2>/dev/null | grep -qF "$node"; then
            node=$(tailscale exit-node suggest 2>/dev/null | sed -n 's/^Suggested exit node: //p' | tr -d '.')
        fi
        if [[ -z "$node" ]]; then
            notify-send -u critical "VPN Error" "No exit nodes available"
        else
            set_node "$node"
        fi
    fi
}

menu_vpn() {
    local -a hosts=() labels=()
    local host label choice i
    while IFS='|' read -r host rest; do
        [[ -z "$host" ]] && continue
        # country/city with trailing status column stripped; fall back to hostname
        label=$(sed -E 's/\s+(selected|offline|-)+\s*$//' <<< "$rest" | xargs)
        if [[ -z "$label" ]] || [[ "$label" =~ ^[-[:space:]]+$ ]]; then
            label=$(pretty "$host")
        fi
        hosts+=("$host")
        labels+=("$label")
    done < <(tailscale exit-node list 2>/dev/null |
        awk '$1 ~ /^[0-9a-fA-F:.]+$/ && NF >= 3 {
            loc = substr($0, index($0, $3))
            print $2 "|" loc
        }')

    [[ ${#hosts[@]} -eq 0 ]] && { notify-send -u critical "VPN" "No exit nodes available"; return 1; }

    choice=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -p "vpn")
    [[ -z "$choice" ]] && return 0
    for i in "${!labels[@]}"; do
        if [[ "${labels[$i]}" == "$choice" ]]; then
            set_node "${hosts[$i]}"
            return 0
        fi
    done
}

case "$1" in
    --toggle) toggle_vpn ;;
    --menu)   menu_vpn ;;
    *)        get_vpn_status ;;
esac
