#!/bin/bash

# --- CONFIGURATION ---
STATE_FILE="$HOME/.config/hypr/wallpaper.env"
TMP_DIR="/tmp/swww_slices"
mkdir -p "$TMP_DIR"

# --- DEFAULTS ---
WIDE_WALLPAPER=""
SINGLE_WALLPAPER=""
WALL_PATHS=() # Array for distinct mode
MODE="SPLIT"   # Options: SPLIT, DISTINCT, FILL

# --- READ STATE ---
[ -f "$STATE_FILE" ] && source "$STATE_FILE"

# --- CHECK DEPENDENCIES ---
for cmd in hyprctl jq socat convert identify swww; do
    if ! command -v "$cmd" &> /dev/null; then
        notify-send "Wallpaper Script" "Missing dependency: $cmd"
        exit 1
    fi
done

# --- FUNCTIONS ---

function get_monitors {
    # Returns monitor names and widths sorted by horizontal position (Left to Right)
    # Format: name width
    hyprctl monitors -j | jq -r 'sort_by(.x) | .[] | "\(.name) \(.width)"'
}

function apply_wallpaper {
    # Small delay to allow Hyprland to finish monitor initialization
    sleep 0.8
    
    # 1. Start swww if not running
    pgrep -x "swww-daemon" > /dev/null || swww-daemon &

    # 2. Get current monitor setup
    mapfile -t MON_DATA < <(get_monitors)
    NUM_MONS=${#MON_DATA[@]}
    
    if [ "$NUM_MONS" -eq 0 ]; then return; fi

    if [ "$NUM_MONS" -eq 1 ] || [ "$MODE" == "FILL" ]; then
        # === SINGLE / FILL MODE ===
        TARGET_IMG="$SINGLE_WALLPAPER"
        [ -z "$TARGET_IMG" ] && TARGET_IMG="$WIDE_WALLPAPER"
        
        if [ -f "$TARGET_IMG" ]; then
            swww img "$TARGET_IMG" --transition-type grow
        fi

    elif [ "$MODE" == "SPLIT" ] && [ -f "$WIDE_WALLPAPER" ]; then
        # === DUAL/MULTI SPLIT MODE (SCALABLE) ===
        
        IMG_W=$(identify -format "%w" "$WIDE_WALLPAPER")
        IMG_H=$(identify -format "%h" "$WIDE_WALLPAPER")
        
        # Calculate Total Physical Width to do proportional splitting
        TOTAL_W=0
        for line in "${MON_DATA[@]}"; do
            W=$(echo "$line" | awk '{print $2}')
            TOTAL_W=$((TOTAL_W + W))
        done

        CURRENT_X_OFFSET=0
        for ((i=0; i<NUM_MONS; i++)); do
            MON_NAME=$(echo "${MON_DATA[$i]}" | awk '{print $1}')
            MON_W=$(echo "${MON_DATA[$i]}" | awk '{print $2}')

            # Calculate slice width proportional to this monitor's resolution
            SLICE_W=$(( MON_W * IMG_W / TOTAL_W ))
            CROP_X=$(( CURRENT_X_OFFSET * IMG_W / TOTAL_W ))
            
            OUTPUT_PATH="$TMP_DIR/slice_$i.png"
            
            # Crop image
            convert "$WIDE_WALLPAPER" -crop "${SLICE_W}x${IMG_H}+${CROP_X}+0" +repage "$OUTPUT_PATH"
            
            # Apply to specific monitor
            swww img "$OUTPUT_PATH" --outputs "$MON_NAME" --transition-type center
            
            CURRENT_X_OFFSET=$((CURRENT_X_OFFSET + MON_W))
        done

    elif [ "$MODE" == "DISTINCT" ]; then
        # === DISTINCT MODE ===
        # Loops through monitors and applies stored paths or fallback
        for ((i=0; i<NUM_MONS; i++)); do
            MON_NAME=$(echo "${MON_DATA[$i]}" | awk '{print $1}')
            # Fallback to single wallpaper if distinct index doesn't exist
            IMG="${WALL_PATHS[$i]:-$SINGLE_WALLPAPER}"
            [ -f "$IMG" ] && swww img "$IMG" --outputs "$MON_NAME"
        done
    fi
}

# --- INITIAL RUN ---
apply_wallpaper

# --- LISTEN FOR EVENTS ---
# Kill existing listeners
for pid in $(pgrep -f "socat.*$HYPRLAND_INSTANCE_SIGNATURE"); do 
    [[ $pid != $$ ]] && kill "$pid" 2>/dev/null
done

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

# Listen for monitor changes and re-trigger application
socat -U - UNIX-CONNECT:"$SOCKET" | while read -r line; do 
    case $line in
        monitoradded*|monitorremoved*) 
            apply_wallpaper 
            ;;
    esac
done