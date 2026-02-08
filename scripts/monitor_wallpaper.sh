#!/bin/bash

# --- CONFIGURATION ---
INTERNAL="eDP-1"
EXTERNAL="HDMI-A-1"
STATE_FILE="$HOME/.config/hypr/wallpaper.env"

# Temp locations for split mode
TMP_LEFT="/tmp/wall_left.png"
TMP_RIGHT="/tmp/wall_right.png"

# --- DEFAULTS ---
WIDE_WALLPAPER=""
SINGLE_WALLPAPER=""
WALL_LEFT=""
WALL_RIGHT=""
MODE="SPLIT" # Default fallback

# --- READ STATE ---
if [ -f "$STATE_FILE" ]; then source "$STATE_FILE"; fi

# --- CHECK DEPENDENCIES ---
for cmd in hyprctl jq socat convert; do
    if ! command -v $cmd &> /dev/null; then exit 1; fi
done

function generate_splits {
    if [ ! -f "$TMP_LEFT" ] || [ "$WIDE_WALLPAPER" -nt "$TMP_LEFT" ]; then
        if [ -f "$WIDE_WALLPAPER" ]; then
            convert "$WIDE_WALLPAPER" -crop 1920x1080+0+0 +repage "$TMP_LEFT"
            convert "$WIDE_WALLPAPER" -crop 1920x1080+1920+0 +repage "$TMP_RIGHT"
        fi
    fi
}

function apply_wallpaper {
    sleep 0.5
    MONITORS=$(hyprctl monitors -j | jq -r '.[].name')
    HAS_INT=$(echo "$MONITORS" | grep -c "$INTERNAL")
    HAS_EXT=$(echo "$MONITORS" | grep -c "$EXTERNAL")

    hyprctl hyprpaper unload all

    if [ "$HAS_INT" -eq 1 ] && [ "$HAS_EXT" -eq 1 ]; then
        # === DUAL MODE ===
        
        if [ "$MODE" == "DISTINCT" ]; then
            # --- Load Distinct Images ---
            if [ -f "$WALL_LEFT" ] && [ -f "$WALL_RIGHT" ]; then
                hyprctl hyprpaper preload "$WALL_LEFT"
                hyprctl hyprpaper preload "$WALL_RIGHT"
                hyprctl hyprpaper wallpaper "$INTERNAL,$WALL_LEFT"
                hyprctl hyprpaper wallpaper "$EXTERNAL,$WALL_RIGHT"
            fi
        else
            # --- Load Split Images (Default) ---
            generate_splits
            if [ -f "$TMP_LEFT" ]; then
                hyprctl hyprpaper preload "$TMP_LEFT"
                hyprctl hyprpaper preload "$TMP_RIGHT"
                hyprctl hyprpaper wallpaper "$INTERNAL,$TMP_LEFT"
                hyprctl hyprpaper wallpaper "$EXTERNAL,$TMP_RIGHT"
            fi
        fi

    else
        # === SINGLE MODE (Laptop only) ===
        if [ -f "$SINGLE_WALLPAPER" ]; then
            hyprctl hyprpaper preload "$SINGLE_WALLPAPER"
            for mon in $MONITORS; do
                hyprctl hyprpaper wallpaper "$mon,$SINGLE_WALLPAPER"
            done
        fi
    fi
}

# --- MAIN LOOP ---
# Kill old instances
for pid in $(pgrep -f "socat.*$HYPRLAND_INSTANCE_SIGNATURE"); do kill $pid; done

# Start hyprpaper
if ! pgrep -x "hyprpaper" > /dev/null; then
    hyprpaper &
    sleep 1
fi

apply_wallpaper

# Listen for monitor events
SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - UNIX-CONNECT:"$SOCKET" | while read -r line; do 
    case $line in
        monitoradded*) apply_wallpaper ;;
        monitorremoved*) apply_wallpaper ;;
    esac
done