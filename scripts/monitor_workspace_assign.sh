#!/bin/bash

# 1. Get monitor names sorted by physical X position (Left to Right)
# Requires 'jq'
mapfile -t monitors < <(hyprctl monitors -j | jq -r 'sort_by(.x) | .[].name')
count=${#monitors[@]}

# Exit if no monitors found
if [ "$count" -eq 0 ]; then exit 0; fi

# 2. Calculate limit (5 workspaces per monitor)
limit=$((count * 5))
batch_cmd=""

# 3. Loop through and assign rules
for ((ws=1; ws<=limit; ws++)); do
    idx=$(( (ws - 1) % count ))
    target=${monitors[$idx]}

    # FIX: Add 'persistent:true' to keep the workspace tethered to the monitor.
    # Optional: Add 'default:true' for the first workspace of each monitor (1, 2, etc.)
    if [ "$ws" -le "$count" ]; then
        rule="monitor:$target,persistent:true,default:true"
    else
        rule="monitor:$target,persistent:true"
    fi

    batch_cmd+="keyword workspace $ws,$rule;"
done

# 4. Execute all rules in one fast IPC call
hyprctl batch "$batch_cmd"