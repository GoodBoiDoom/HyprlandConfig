#!/bin/bash

# --- CONFIGURATION ---
INTERNAL="eDP-1"     
EXTERNAL="HDMI-A-1"
STATE_FILE="$HOME/.config/hypr/wallpaper.env"

# --- LOAD PREVIOUS STATE ---
# We load the file first so we remember what the "other" monitor is set to
# when we only change one of them.
if [ -f "$STATE_FILE" ]; then source "$STATE_FILE"; fi

# Temp paths for split mode
TMP_LEFT="/tmp/wall_left.png"
TMP_RIGHT="/tmp/wall_right.png"

# --- FUNCTIONS ---

function save_state {
    # Writes all current variables to the file
    cat <<EOT > "$STATE_FILE"
WIDE_WALLPAPER="$WIDE_WALLPAPER"
SINGLE_WALLPAPER="$SINGLE_WALLPAPER"
WALL_LEFT="$WALL_LEFT"
WALL_RIGHT="$WALL_RIGHT"
MODE="$MODE"
EOT
}

function get_image {
    zenity --file-selection --title="$1" --file-filter="Images | *.jpg *.jpeg *.png *.webp"
}

function set_wall {
    # $1 = Monitor, $2 = Image Path
    if [ ! -z "$2" ] && [ -f "$2" ]; then
        hyprctl hyprpaper unload "$2"
        hyprctl hyprpaper preload "$2"
        hyprctl hyprpaper wallpaper "$1,$2"
    fi
}

# --- MENU OPTIONS ---
OPT_SPLIT="Split Wide Image (Dual)"
OPT_DIST="Distinct Images (Dual - Both)"
OPT_LEFT="Left Screen Only ($INTERNAL)"
OPT_RIGHT="Right Screen Only ($EXTERNAL)"
OPT_FILL="Single Image (Laptop/All)"
# Show Menu
CHOICE=$(echo -e "$OPT_SPLIT\n$OPT_DIST\n$OPT_LEFT\n$OPT_RIGHT\n$OPT_FILL" | rofi -dmenu -p "Wallpaper Mode" -lines 5)

case "$CHOICE" in
    "$OPT_SPLIT")
        IMG=$(get_image "Select Wide Wallpaper")
        [ -z "$IMG" ] && exit 0

        # Update State
        WIDE_WALLPAPER="$IMG"
        MODE="SPLIT"
        save_state

        notify-send "Wallpaper" "Cropping and applying..."
        
        # Crop
        convert "$IMG" -crop 1920x1080+0+0 +repage "$TMP_LEFT"
        convert "$IMG" -crop 1920x1080+1920+0 +repage "$TMP_RIGHT"
        
        # Apply
        set_wall "$INTERNAL" "$TMP_LEFT"
        set_wall "$EXTERNAL" "$TMP_RIGHT"
        ;;

    "$OPT_DIST")
        # Change BOTH individually
        IMG_L=$(get_image "Select Image for LEFT ($INTERNAL)")
        [ -z "$IMG_L" ] && exit 0
        
        IMG_R=$(get_image "Select Image for RIGHT ($EXTERNAL)")
        [ -z "$IMG_R" ] && exit 0

        # Update State
        WALL_LEFT="$IMG_L"
        WALL_RIGHT="$IMG_R"
        MODE="DISTINCT"
        save_state

        # Apply
        set_wall "$INTERNAL" "$WALL_LEFT"
        set_wall "$EXTERNAL" "$WALL_RIGHT"
        notify-send "Wallpaper" "Distinct wallpapers applied!"
        ;;

    "$OPT_LEFT")
        # Change LEFT only
        IMG=$(get_image "Select Image for LEFT ($INTERNAL)")
        [ -z "$IMG" ] && exit 0

        # Update State
        WALL_LEFT="$IMG"
        MODE="DISTINCT" # Switch mode so we don't auto-crop on reboot
        save_state

        set_wall "$INTERNAL" "$WALL_LEFT"
        notify-send "Wallpaper" "Left monitor updated!"
        ;;

    "$OPT_RIGHT")
        # Change RIGHT only
        IMG=$(get_image "Select Image for RIGHT ($EXTERNAL)")
        [ -z "$IMG" ] && exit 0

        # Update State
        WALL_RIGHT="$IMG"
        MODE="DISTINCT" # Switch mode so we don't auto-crop on reboot
        save_state

        set_wall "$EXTERNAL" "$WALL_RIGHT"
        notify-send "Wallpaper" "Right monitor updated!"
        ;;

    "$OPT_FILL")
        # Apply one image to everything
        IMG=$(get_image "Select Single Wallpaper")
        [ -z "$IMG" ] && exit 0

        # Update State
        SINGLE_WALLPAPER="$IMG"
        save_state

        MONITORS=$(hyprctl monitors -j | jq -r '.[].name')
        for mon in $MONITORS; do
            set_wall "$mon" "$IMG"
        done
        notify-send "Wallpaper" "Single wallpaper applied!"
        ;;
esac